-- git-actions.lua
-- Phase 3 Git-only operations: push, branch management, and switch.
local Config = require(".config")
local Git = require(".core-git")
local Notify = require(".core-notify")
local Runner = require(".core-runner")
local Scope = require(".core-scope")
local State = require(".core-state")
local Temp = require(".core-temp")

local M = {}

local function root_for_git(cfg)
	local scope = Scope.resolve_or_notify(cfg)
	if not scope then return nil end
	if scope.kind ~= "git" then
		Notify.warn("This Git-only operation requires a Git repository.")
		return nil
	end
	return scope
end

local function run(root, args, cfg)
	return Runner.run({ command = "git", args = args, cwd = root }, cfg.runner.timeout_ms, cfg.runner.audit)
end

local function fail(operation, output, err)
	Notify.error("%s failed: %s", operation, Runner.summary(Runner.error_text(output, err), 240))
end

local function with_lock(root, operation, fn)
	if not State.begin_action(root) then
		Notify.warn("Another VCS operation is already running for this repository.")
		return
	end
	local ok, result = pcall(fn)
	State.end_action(root)
	if not ok then error(result, 0) end
	return result
end

local function refresh(root, message)
	State.clear_root(root)
	ya.emit("refresh", {})
	Notify.info("%s", message)
end

local function ask(title, initial_value)
	local options = { title = title, pos = { "center", w = 60 } }
	if initial_value ~= nil then options.value = initial_value end
	local value, event = ya.input(options)
	if event ~= 1 then return nil end
	return value
end

local function validate_name(root, name, cfg)
	local valid, reason = Git.validate_name_input(name)
	if not valid then
		Notify.error("Invalid branch name: %s", reason)
		return false
	end
	local output, err = run(root, Git.check_ref_format_args(name), cfg)
	if not output or not output.status.success then
		fail("Branch name validation", output, err)
		return false
	end
	return true
end

local function branch_data(root, cfg, include_remote)
	if include_remote == nil then include_remote = cfg.git.branch.show_remote ~= false end
	local output, err = run(root, Git.branch_list_args(include_remote), cfg)
	if not output or not output.status.success then
		fail("Branch list", output, err)
		return nil
	end
	return Git.parse_branches(output.stdout), output.stdout
end

function M.push()
	local cfg = Config.get()
	local scope = root_for_git(cfg)
	if not scope then return end
	local root = scope.root
	with_lock(root, "Git push", function()
		local branch_output, branch_err = run(root, Git.current_branch_args(), cfg)
		local branch = branch_output and branch_output.status.success and branch_output.stdout:gsub("%s+$", "") or ""
		if not branch or branch == "" then
			return Notify.error("Git push is unavailable in detached HEAD state: %s", Runner.summary(Runner.error_text(branch_output, branch_err), 240))
		end

		local upstream_output, upstream_err = run(root, Git.upstream_args(), cfg)
		local has_upstream = upstream_output and upstream_output.status.success
		local args
		if has_upstream then
			args = Git.push_args(nil, nil, false)
		else
			if cfg.git.push.set_upstream_if_missing == false then
				return Notify.error("No upstream is configured for branch %s.", branch)
			end
			local remotes_output, remotes_err = run(root, Git.remote_args(), cfg)
			if not remotes_output or not remotes_output.status.success then return fail("Git remote list", remotes_output, remotes_err) end
			local remotes = Git.parse_lines(remotes_output.stdout)
			if #remotes == 0 then return Notify.error("Git push failed: no remote is configured.") end
			local remote = nil
			for _, candidate in ipairs(remotes) do
				if candidate == cfg.git.push.default_remote then remote = candidate end
			end
			if not remote and #remotes == 1 then remote = remotes[1] end
			if not remote then
				local answer = ask("Remote for " .. branch .. " (" .. table.concat(remotes, ", ") .. "):")
				if not answer or answer == "" then return Notify.info("Git push cancelled.") end
				for _, candidate in ipairs(remotes) do if candidate == answer then remote = candidate end end
			end
			if not remote then return Notify.error("Unknown Git remote.") end
			args = Git.push_args(remote, branch, true)
		end

		-- Push may request credentials, so it deliberately bypasses the timeout
		-- runner and inherits the terminal while Yazi is hidden.
		local status, err = Runner.interactive({ command = "git", args = args, cwd = root }, cfg.runner.audit)
		if not status or not status.success then
			return fail("Git push", status and { status = status, stderr = "" } or nil, err)
		end
		refresh(root, "Git push completed.")
	end)
end

local function branch_list(root, cfg)
	local branches, raw = branch_data(root, cfg, cfg.git.branch.show_remote ~= false)
	if not branches then return end
	local ok, err = Temp.display(raw, cfg, Runner)
	if not ok then Notify.error("Branch list could not be displayed: %s", err) end
end

local function branch_create(root, cfg, switch_after)
	local name = ask("New branch name:")
	if not name or not validate_name(root, name, cfg) then return end
	local start = ask("Start point (optional):")
	if start and start ~= "" then
		local valid, reason = Git.validate_ref_input(start, "start point")
		if not valid then return Notify.error("Invalid start point: %s", reason) end
	end
	local args = Git.create_branch_args(name, start, switch_after)
	local output, err = run(root, args, cfg)
	if not output or not output.status.success then return fail("Branch create", output, err) end
	refresh(root, switch_after and ("Created and switched to branch: " .. name) or ("Created branch: " .. name))
end

local function branch_rename(root, cfg, old_name)
	if old_name and old_name ~= "" then
		local valid, reason = Git.validate_ref_input(old_name, "old branch name")
		if not valid then return Notify.error("Invalid old branch name: %s", reason) end
	end
	local new_name = ask("New branch name:")
	if not new_name or not validate_name(root, new_name, cfg) then return end
	local args = Git.rename_branch_args(old_name, new_name)
	local output, err = run(root, args, cfg)
	if not output or not output.status.success then return fail("Branch rename", output, err) end
	refresh(root, "Renamed branch to: " .. new_name)
end

local function branch_delete(root, cfg)
	local branches = branch_data(root, cfg, true)
	if not branches then return end
	local name = ask("Local branch to delete:")
	if not name or name == "" then return end
	local selected = Git.find_branch(branches, name)
	if not selected then return Notify.error("Branch not found: %s", name) end
	if selected.remote then return Notify.error("Remote branches cannot be deleted by this action.") end
	if selected.current then return Notify.error("The current branch cannot be deleted.") end
	-- ya.confirm() does not render in the functional plugin task on
	-- Windows and leaves the task pending indefinitely (see issue #22,
	-- which hit the same problem in Discard); ya.input() is the
	-- confirmed-working alternative.
	local body = "Delete local branch " .. name .. " safely?\n\nOnly `git branch -d` will be used."
	local value, event = ya.input({ title = 'Type "delete" to confirm:\n' .. body, pos = { "center", w = 60 } })
	if event ~= 1 or value ~= "delete" then return end
	local output, err = run(root, Git.delete_branch_args(name), cfg)
	if not output or not output.status.success then return fail("Branch delete", output, err) end
	refresh(root, "Deleted branch: " .. name)
end

function M.branch(subaction)
	local cfg = Config.get()
	local scope = root_for_git(cfg)
	if not scope then return end
	local root = scope.root
	with_lock(root, "Git branch", function()
		local action = subaction or ask("Branch action (list/create/create-switch/rename/delete):")
		if action == "list" then return branch_list(root, cfg) end
		if action == "create" then return branch_create(root, cfg, false) end
		if action == "create-switch" then return branch_create(root, cfg, true) end
		if action == "rename" then
			local old_name = ask("Branch to rename (empty=current):")
			if old_name == nil then return end
			return branch_rename(root, cfg, old_name)
		end
		if action == "delete" then return branch_delete(root, cfg) end
		if action == nil or action == "" then return end
		Notify.warn("Unknown branch action: %s", tostring(action))
	end)
end

function M.switch()
	local cfg = Config.get()
	local scope = root_for_git(cfg)
	if not scope then return end
	local root = scope.root
	with_lock(root, "Git switch", function()
		local name = ask("Branch or remote branch to switch to:")
		if not name or name == "" then return end
		local branches = branch_data(root, cfg, true)
		if not branches then return end
		local local_branch = Git.find_branch(branches, name)
		local remote_branch = nil
		for _, branch in ipairs(branches) do
			if branch.name == name and branch.remote then remote_branch = branch end
		end
		local args
		if local_branch and not local_branch.remote then
			args = Git.switch_branch_args(name)
		elseif remote_branch then
			if cfg.git.switch.auto_track_remote == false then return Notify.error("No local branch exists for remote %s.", name) end
			args = Git.switch_branch_args(name, name, nil)
		else
			return Notify.error("Local or remote branch not found: %s", name)
		end
		local output, err = run(root, args, cfg)
		if not output or not output.status.success then return fail("Git switch", output, err) end
		refresh(root, "Switched to branch: " .. name)
	end)
end

function M.entry(action, args)
	if action == "push" then return M.push() end
	if action == "branch" then return M.branch(args and args[2]) end
	if action == "switch" then return M.switch() end
	Notify.warn("Unknown Git action: %s", tostring(action))
end

return M
