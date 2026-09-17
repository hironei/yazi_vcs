-- Git/SVN file operations: delete, rename with native VCS move, and split-tabs transfer.
local Config = require(".config")
local Commands = require(".core-commands")
local Context = require(".core-context")
local Detector = require(".core-detector")
local Git = require(".core-git")
local Notify = require(".core-notify")
local Path = require(".core-path")
local Runner = require(".core-runner")
local State = require(".core-state")
local Targets = require(".core-targets")
local SvnBackend = require(".backend-svn")

local M = {}

local function display_path(path)
	return Runner.summary(tostring(path or ""), 120)
end

local function run(kind, root, args, cfg)
	return Runner.run({ command = kind, args = args, cwd = root }, cfg.runner.timeout_ms)
end

local function tracked_directory(root, path, cfg)
	local output, err = run("git", root, { "--literal-pathspecs", "ls-files", "--cached", "--", path }, cfg)
	if not output or not output.status.success then return nil, err or Runner.error_text(output) end
	return tostring(output.stdout or ""):match("%S") ~= nil
end

local function versioned_path(kind, root, path, cfg)
	if kind == "git" then return tracked_directory(root, path, cfg) end
	local output, err = run("svn", root, SvnBackend.versioned_path_args(path), cfg)
	if not output then return nil, err or "could not query SVN path metadata" end
	if output.timed_out then return nil, Runner.error_text(output, err) end
	if not output.status.success then return false end
	local item = Runner.summary(output.stdout, 40)
	return item == "directory" or item == "file"
end

local function move_args(kind, paths, destination)
	if kind == "git" then return Git.move_args(paths, destination) end
	return Commands.svn_move(paths, destination)
end

local function delete_args(kind, paths)
	if kind == "git" then return Commands.git_delete(paths) end
	return Commands.svn_delete(paths)
end

local function fail(kind, operation, output, err)
	local name = kind == "svn" and "SVN" or "Git"
	Notify.error("%s %s failed: %s", name, operation, Runner.summary(Runner.error_text(output, err), 240))
end

local function runner_error_message(err)
	return tostring(err or "unknown error"):gsub("^[^\r\n]-:%d+: ", "")
end

local function with_lock(root, fn)
	if not State.begin_action(root) then
		Notify.warn("Another VCS operation is already running for this repository.")
		return
	end
	local ok, result = pcall(fn)
	State.end_action(root)
	if not ok then error(result, 0) end
	return result
end

local function ask(title, initial_value)
	local options = { title = title, pos = { "center", w = 60 } }
	if initial_value ~= nil then options.value = initial_value end
	local value, event = ya.input(options)
	if event ~= 1 then return nil end
	return value
end

local function root_for_path(path, is_dir, cfg)
	local start = is_dir and path or Path.parent(path)
	return Detector.detect(Url(start), cfg.detection.priority)
end

local function root_for_file_operation(context, sources, destination, cfg)
	if context.active_search then
		Notify.warn("VCS file operations are unavailable in Search View.")
		return nil
	end
	local kind, root = root_for_path(context.active_cwd, true, cfg)
	if not kind or not root then
		Notify.warn("This operation requires a Git repository or SVN working copy.")
		return nil
	end
	for _, source in ipairs(sources) do
		if source.search then
			Notify.warn("VCS file operations are unavailable in Search View.")
			return nil
		end
		local source_kind, source_root = root_for_path(source.path, source.is_dir, cfg)
		if not source_kind or not source_root then
			Notify.error("Refusing VCS file operation outside a working copy: %s", display_path(source.path))
			return nil
		end
		if kind ~= source_kind or not Path.same(root, source_root) then
			Notify.error("All source items must belong to the active pane's same VCS working copy.")
			return nil
		end
	end
	if destination then
		if context.other_search then
			Notify.warn("VCS file operations are unavailable when the other pane shows Search View.")
			return nil
		end
		local destination_kind, destination_root = root_for_path(destination, true, cfg)
		if not destination_kind or not destination_root then
			Notify.error("The other pane is outside a VCS working copy: %s", display_path(destination))
			return nil
		end
		if kind ~= destination_kind or not Path.same(root, destination_root) then
			Notify.error("The other pane must be inside the same VCS working copy as the source items.")
			return nil
		end
	end
	return { kind = kind, root = root }
end

local function refresh_after_mutation(root)
	State.clear_root(root)
	-- split-tabs watches and relays updates for both pane directories; this
	-- refresh also immediately reloads the active pane after a path move.
	ya.emit("refresh", {})
end

local function file_source_exists(source)
	local ok, cha = pcall(function() return fs.cha(Url(source.path), true) end)
	if not ok or not cha then return false end
	if cha.is_dir == true then source.is_dir = true end
	return true
end

function M.rename()
	local cfg = Config.get()
	local context = Context.file_operation_snapshot()
	local sources = Targets.choose_file_sources(context.selected, context.hovered)
	local source, reason = Targets.single_file_source(sources)
	if not source then
		if reason == "multiple" then return Notify.error("Rename requires exactly one selected item.") end
		return Notify.warn("No file selected or hovered for rename.")
	end
	local scope = root_for_file_operation(context, { source }, nil, cfg)
	if not scope then return end
	local relative = Path.strip_prefix(scope.root, source.path)
	if not relative or relative == "" then return Notify.error("Refusing to rename the VCS working-copy root.") end

	return with_lock(scope.root, function()
		if not file_source_exists(source) then return Notify.error("Rename source no longer exists: %s", display_path(source.path)) end
		local old_name = Path.basename(relative)
		local new_name = ask("New name for " .. tostring(old_name) .. ":", old_name)
		if new_name == nil or new_name == "" then return Notify.info("Rename cancelled.") end
		local destination, invalid = Targets.rename_path(relative, new_name)
		if not destination then return Notify.error("Invalid rename: %s", invalid) end
		if destination == relative then return Notify.info("Rename cancelled: the name is unchanged.") end
		local destination_absolute = Path.join_native(scope.root, destination, package.config:sub(1, 1) == "\\")
		local target_ok, target = pcall(function() return fs.cha(Url(destination_absolute), true) end)
		if not target_ok then return Notify.error("Cannot inspect rename destination: %s", display_path(destination)) end
		if target then return Notify.error("Rename destination already exists: %s", display_path(new_name)) end

		local ok, output, err = pcall(run, scope.kind, scope.root, move_args(scope.kind, { relative }, destination), cfg)
		refresh_after_mutation(scope.root)
		if not ok then return fail(scope.kind, "rename", nil, runner_error_message(output)) end
		if not output or not output.status or not output.status.success then return fail(scope.kind, "rename", output, err) end
		Notify.info("Renamed with %s move: %s", scope.kind, display_path(new_name))
	end)
end

function M.move_other_pane()
	local cfg = Config.get()
	local context = Context.file_operation_snapshot()
	if context.tab_count ~= 2 or not context.other_cwd then
		return Notify.warn("Move to the other pane requires the active two-tab split-tabs layout.")
	end
	local sources = Targets.choose_file_sources(context.selected, context.hovered)
	if #sources == 0 then return Notify.warn("No files selected or hovered for move.") end
	local scope = root_for_file_operation(context, sources, context.other_cwd, cfg)
	if not scope then return end

	return with_lock(scope.root, function()
		local cwd_ok, cwd_cha = pcall(function() return fs.cha(Url(context.other_cwd), true) end)
		if not cwd_ok or not cwd_cha or cwd_cha.is_dir ~= true then
			return Notify.error("The other pane's current path is not an existing directory.")
		end
		for _, source in ipairs(sources) do
			if not file_source_exists(source) then return Notify.error("Move source no longer exists: %s", display_path(source.path)) end
		end
		local plan, plan_error = Targets.plan_move(
			scope.root,
			sources,
			context.other_cwd,
			function(path)
				local ok, cha = pcall(function() return fs.cha(Url(path), true) end)
				if not ok then return nil, cha end
				return cha ~= nil
			end,
			package.config:sub(1, 1) == "\\"
		)
		if not plan then
			if plan_error.code == "outside" then return Notify.error("Refusing move outside the working copy: %s", display_path(plan_error.path)) end
			if plan_error.code == "inside-source" then return Notify.error("Cannot move a directory into itself or one of its descendants.") end
			if plan_error.code == "collision" or plan_error.code == "duplicate" then return Notify.error("Move destination already exists: %s", display_path(plan_error.path)) end
			if plan_error.code == "inspect-error" then return Notify.error("Cannot inspect move destination: %s", display_path(plan_error.path)) end
			return Notify.error("Move could not be planned safely.")
		end

		local ok, output, err = pcall(run, scope.kind, scope.root, move_args(scope.kind, plan.paths, plan.destination), cfg)
		refresh_after_mutation(scope.root)
		if not ok then return fail(scope.kind, "move", nil, runner_error_message(output)) end
		if not output or not output.status or not output.status.success then return fail(scope.kind, "move", output, err) end
		Notify.info("Move to other pane completed with %s.", scope.kind == "svn" and "svn move" or "git mv")
	end)
end

function M.delete()
	local cfg = Config.get()
	local context = Context.file_operation_snapshot()
	local sources = Targets.choose_file_sources(context.selected, context.hovered)
	if #sources == 0 then return Notify.warn("No files selected or hovered for delete.") end
	local scope = root_for_file_operation(context, sources, nil, cfg)
	if not scope then return end

	return with_lock(scope.root, function()
		local relative = {}
		for _, source in ipairs(sources) do
			if not file_source_exists(source) then
				return Notify.error("Delete source no longer exists: %s", display_path(source.path))
			end
			local path = Path.strip_prefix(scope.root, source.path)
			if not path or path == "" then
				return Notify.error("Refusing to delete the VCS working-copy root.")
			end
			relative[#relative + 1] = path
		end

		local statuses = {}
		for _, path in ipairs(relative) do statuses[path] = State.status_of(scope.root, path) end
		local versioned = {}
		if scope.kind == "git" or scope.kind == "svn" then
			for i, source in ipairs(sources) do
				local path = relative[i]
				if source.is_dir and statuses[path] == "untracked" then
					local tracked, tracked_err = versioned_path(scope.kind, scope.root, path, cfg)
					if tracked == nil then return fail(scope.kind, "status", nil, tracked_err) end
					versioned[path] = tracked
				end
			end
		end
		local kept, excluded = Targets.exclude_untracked(relative, statuses, versioned)
		if #excluded > 0 then
			Notify.warn("Untracked/ignored targets were excluded: " .. table.concat(excluded, ", "))
		end
		if #kept == 0 then return end

		local body = "Delete these version-controlled paths?\n\n" .. Targets.describe(kept)
		local value, event = ya.input({
			title = 'Type "delete" to confirm:\n' .. body,
			pos = { "center", w = 60 },
		})
		if event ~= 1 or value ~= "delete" then return Notify.info("Delete cancelled.") end

		local ok, output, err = pcall(run, scope.kind, scope.root, delete_args(scope.kind, kept), cfg)
		refresh_after_mutation(scope.root)
		if not ok then return fail(scope.kind, "delete", nil, runner_error_message(output)) end
		if not output or not output.status or not output.status.success then return fail(scope.kind, "delete", output, err) end
		Notify.info("%s delete completed.", scope.kind == "svn" and "SVN" or "Git")
	end)
end

function M.entry(action)
	if action == "rename" then return M.rename() end
	if action == "move-other-pane" then return M.move_other_pane() end
	if action == "delete" then return M.delete() end
	Notify.warn("Unknown VCS file action: %s", tostring(action))
end

return M
