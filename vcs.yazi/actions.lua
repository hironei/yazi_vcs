-- actions.lua
-- Phase 2 common VCS operations plus Phase 4 external viewers.
local Config = require(".config")
local Detector = require(".core-detector")
local External = require(".core-external")
local Notify = require(".core-notify")
local Runner = require(".core-runner")
local State = require(".core-state")
local Targets = require(".core-targets")
local Commands = require(".core-commands")

local M = {}

local function trace(stage)
	if os.getenv("VCS_YAZI_TRACE") == "1" and type(ya.err) == "function" then
		ya.err("vcs trace: " .. stage)
	end
end

local current_context = ya.sync(function()
	local tab, selected, info = cx.active, {}, {}
	for _, url in pairs(tab.selected) do
		local path = tostring(url)
		selected[#selected + 1] = path
		info[path] = false
	end
	for i = 1, #tab.current.files do
		local file = tab.current.files[i]
		if file then info[tostring(file.url)] = file.cha and file.cha.is_dir or false end
	end
	local hovered = tab.current.hovered
	local hovered_path = hovered and tostring(hovered.url) or nil
	if hovered_path then info[hovered_path] = hovered.cha and hovered.cha.is_dir or false end
	return selected, hovered_path, tostring(tab.current.cwd), info
end)

local function context_root(cwd, cfg)
	local kind, root = Detector.detect(Url(cwd), cfg.detection.priority)
	if not kind then
		Notify.warn("Not inside a Git or SVN working copy.")
		return nil
	end
	return kind, root
end

local function selected_targets(root)
	local selected, hovered, cwd, info = current_context()
	local absolute, scope = Targets.choose(selected, hovered, cwd)
	local relative, invalid = Targets.relative(absolute, root)
	if not relative then
		Notify.error("Refusing VCS operation outside the repository: %s", invalid)
		return nil
	end
	return relative, scope, info, absolute
end

local function run(root, command, args, cfg)
	return Runner.run({ command = command, args = args, cwd = root }, cfg.runner.timeout_ms)
end

local function argv(configured, fallback_command, fallback_args)
	if type(configured) ~= "table" or not configured[1] then
		return fallback_command, fallback_args
	end
	local args = {}
	for i = 2, #configured do args[#args + 1] = configured[i] end
	return configured[1], args
end

local function expand_template(template, paths)
	local expanded = {}
	for _, token in ipairs(template or {}) do
		if token == "{targets}" then
			for _, path in ipairs(paths or {}) do expanded[#expanded + 1] = path end
		else
			expanded[#expanded + 1] = token
		end
	end
	return expanded
end

local function finish(root, operation, output)
	State.clear_root(root)
	ya.emit("refresh", {})
	local summary = Runner.summary(output and output.stdout)
	Notify.info(summary ~= "" and "%s completed: %s" or "%s completed.", operation, summary)
end

local function with_lock(root, operation, fn, read_only)
	if read_only then
		-- A functional plugin's entry already runs in Yazi's async task. On
		-- Windows, wrapping this read-only closure in xpcall can leave that task
		-- pending before its body starts. Let Yazi surface any Lua error instead.
		return fn()
	end
	if not State.begin_action(root) then
		Notify.warn("Another VCS operation is already running for this repository.")
		return
	end
	-- Keep the cleanup explicit. Wrapping the async operation in xpcall can
	-- leave the task pending on Windows before the operation body starts.
	local result = fn()
	State.end_action(root)
	return result
end

local function failure(operation, output, err)
	Notify.error("%s failed: %s", operation, Runner.error_text(output, err))
end

local function temp_file(content)
	local path = os.tmpname()
	local file, err = io.open(path, "w")
	if not file then return nil, err end
	file:write(content or "")
	file:close()
	return path
end

--- Write view output through Yazi's async filesystem API. `view_operation`
--- runs in an async plugin context, where Lua's blocking `io.open()` can
--- leave the task pending on Windows before the pager is started.
local function temp_output_file(content)
	local url = Url(os.tmpname())
	local path = tostring(url)
	local ok, err = fs.write(url, content or "")
	if not ok then return nil, err end
	return path
end

local function read_file(path)
	local file, err = io.open(path, "r")
	if not file then return nil, err end
	local content = file:read("*a")
	file:close()
	return content
end

local function remove_file(path)
	if path then os.remove(path) end
end

local function remove_output_file(path)
	if path then fs.remove("file", Url(path)) end
end

local function has_message(content)
	for line in tostring(content or ""):gmatch("[^\r\n]+") do
		if line:match("%S") and not line:match("^%s*#") then return true end
	end
	return false
end

local function edit_message(path, cfg)
	local editor = cfg.editor
	if not editor or not editor.command or editor.command == "" then return nil, "editor is not configured" end
	local args = {}
	for _, value in ipairs(editor.args or {}) do args[#args + 1] = value end
	args[#args + 1] = path
	local status, err = Runner.interactive({ command = editor.command, args = args })
	if not status then return nil, err end
	if not status.success then return nil, "editor exited with code " .. tostring(status.code or "unknown") end
	return read_file(path)
end

local function display_file(path, cfg)
	local viewer = cfg.pager and cfg.pager.command and cfg.pager.command ~= "" and cfg.pager or cfg.editor
	if not viewer or not viewer.command or viewer.command == "" then return nil, "pager/editor is not configured" end
	local args = {}
	for _, value in ipairs(viewer.args or {}) do args[#args + 1] = value end
	args[#args + 1] = path
	local status, err = Runner.interactive({ command = viewer.command, args = args })
	if not status then return nil, err end
	if not status.success then return nil, "viewer exited with code " .. tostring(status.code or "unknown") end
	return true
end

local function debug_log(message)
	if type(ya.dbg) == "function" then pcall(ya.dbg, message) end
end

local function convert_external_path(path, style, environment, root, cfg)
	if style ~= "windows" or (environment ~= "wsl" and environment ~= "git-bash") then return path end
	local converter = External.converter(environment)
	if not converter then return path end
	local output, err = Runner.run({ command = converter, args = { "-w", "--", path }, cwd = root }, cfg.runner.timeout_ms)
	if output and output.status.success then
		local converted = tostring(output.stdout):gsub("%s+$", "")
		if converted ~= "" then return converted end
	end
	debug_log("VCS external path conversion unavailable for " .. tostring(path) .. ": " .. Runner.error_text(output, err))
	return path
end

local function external_context(root, absolute, cfg, spec)
	local environment = External.environment({
		WSL_INTEROP = os.getenv("WSL_INTEROP"),
		WSL_DISTRO_NAME = os.getenv("WSL_DISTRO_NAME"),
		WSLENV = os.getenv("WSLENV"),
		MSYSTEM = os.getenv("MSYSTEM"),
		MSYSTEM_PREFIX = os.getenv("MSYSTEM_PREFIX"),
		CYGWIN = os.getenv("CYGWIN"),
	}, ya.target_family())
	local style = External.path_style(spec.path_style or (cfg.path and cfg.path.external_style), environment)
	local root_path = convert_external_path(root, style, environment, root, cfg)
	local targets = {}
	for _, path in ipairs(absolute or {}) do targets[#targets + 1] = convert_external_path(path, style, environment, root, cfg) end
	local file = targets[1] or root_path
	return { root = root_path, file = file, targets = targets, revision = spec.revision or "" }
end

local function run_external(root, operation, spec, absolute, cfg)
	local valid, reason = External.validate(spec)
	if not valid then return Notify.error("%s is not configured: %s", operation, reason) end
	local context = external_context(root, absolute, cfg, spec)
	local args, expand_err = External.expand_args(spec.args, context)
	if not args then return Notify.error("%s configuration is invalid: %s", operation, expand_err) end
	trace("external: " .. operation .. " command=" .. tostring(spec.command) .. " cwd=" .. tostring(root) .. " args=" .. table.concat(args, " | "))
	local command = { command = spec.command, args = args, cwd = root }
	if spec.interactive == false then
		local launched, launch_err = Runner.launch(command)
		trace("external:orphan-launch=" .. tostring(launched) .. " error=" .. tostring(launch_err))
		if not launched then return failure(operation, nil, launch_err) end
		return Notify.info("%s launched.", operation)
	end
	local status, err = Runner.interactive(command)
	if not status or not status.success then return failure(operation, status and { status = status } or nil, err) end
	Notify.info("%s completed.", operation)
end

local function has_diff(root, kind, paths)
	local args = kind == "git" and Commands.git_diff(paths) or Commands.svn_diff(paths)
	local output, err = Runner.output({ command = kind, args = args, cwd = root })
	if not output or not output.status.success then return nil, output, err end
	return Runner.summary(output.stdout, 1) ~= "", output, nil
end

function M.update()
	local cfg = Config.get()
	local _, _, cwd = current_context()
	local kind, root = context_root(cwd, cfg)
	if not kind then return end
	with_lock(root, "Update", function()
		local fallback = kind == "git" and Commands.git_update() or Commands.svn_update(nil)
		local command, args = argv(cfg.update and cfg.update[kind], kind, fallback)
		local output, err = run(root, command, args, cfg)
		local operation = kind:gsub("^%l", string.upper) .. " update"
		if not output or not output.status.success then return failure(operation, output, err) end
		finish(root, operation, output)
	end)
end

function M.commit()
	local cfg = Config.get()
	local _, _, cwd = current_context()
	local kind, root = context_root(cwd, cfg)
	if not kind then return end
	with_lock(root, "Commit", function()
		local paths = selected_targets(root)
		if not paths or #paths == 0 then return Notify.warn("No VCS target selected.") end
		local mode = kind == "git" and cfg.commit.git_mode or nil
		local body = "Commit " .. #paths .. " target(s)?\n\n" .. Targets.describe(paths)
		if kind == "git" and mode ~= "staged" then body = body .. "\n\nSelected paths are staged implicitly by Git." end
		if not ya.confirm({ title = "VCS Commit", body = body }) then return end
		local message_file, temp_err = temp_file("")
		if not message_file then return Notify.error("Cannot create commit message file: %s", temp_err) end
		local content, edit_err = edit_message(message_file, cfg)
		if not content then
			remove_file(message_file)
			return Notify.warn("Commit cancelled: %s", edit_err or "empty editor result")
		end
		if not has_message(content) and not cfg.commit.allow_empty_message then
			remove_file(message_file)
			return Notify.warn("Commit cancelled: the message is empty.")
		end
		local fallback = kind == "git" and Commands.git_commit(message_file, paths, mode) or Commands.svn_commit(message_file, paths)
		local output, err = run(root, kind, fallback, cfg)
		remove_file(message_file)
		local operation = kind:gsub("^%l", string.upper) .. " commit"
		if not output or not output.status.success then return failure(operation, output, err) end
		finish(root, operation, output)
	end)
end

local function view_operation(operation, config_section, kind_builder, external)
	local cfg = Config.get()
	local _, _, cwd = current_context()
	local kind, root = context_root(cwd, cfg)
	if not kind then return end
	with_lock(root, operation, function()
		local paths, _, _, absolute = selected_targets(root)
		if not paths then return end
		local section = cfg[config_section] or {}
		if external then
			if config_section == "diff" then
				local changed, output, err = has_diff(root, kind, paths)
				if changed == nil then return failure(operation .. " check", output, err) end
				if not changed then return Notify.info("%s: no differences for selected targets.", operation) end
			end
			return run_external(root, operation .. " (external)", section[kind .. "_external"], absolute, cfg)
		end
		local configured = section[kind .. "_cli"]
		local fallback = kind_builder(kind, paths)
		local command, args
		if configured then
			command, args = argv(configured, kind, fallback)
			args = expand_template(args, paths)
		else
			command, args = kind, fallback
		end
		local output, err = Runner.output({ command = command, args = args, cwd = root })
		if not output or not output.status.success then return failure(operation, output, err) end
		if Runner.summary(output.stdout, 1) == "" then return Notify.info("No output from %s.", operation) end
		local file, temp_err = temp_output_file(output.stdout)
		if not file then return Notify.error("Cannot create output file: %s", temp_err) end
		local shown, display_err = display_file(file, cfg)
		remove_output_file(file)
		if not shown then return Notify.error("%s output could not be displayed: %s", operation, display_err) end
	end, true)
end

function M.diff(external)
	return view_operation("Diff", "diff", function(kind, paths)
		return kind == "git" and Commands.git_diff(paths) or Commands.svn_diff(paths)
	end, external)
end

function M.log(external)
	return view_operation("Log", "log", function(kind, paths)
		return kind == "git" and Commands.git_log(paths) or Commands.svn_log(paths)
	end, external)
end

function M.discard()
	local cfg = Config.get()
	local _, _, cwd = current_context()
	local kind, root = context_root(cwd, cfg)
	if not kind then return end
	trace("discard:start kind=" .. kind .. " root=" .. tostring(root))
	with_lock(root, "Discard", function()
		local paths, _, info, absolute = selected_targets(root)
		if not paths then return end
		trace("discard:targets=" .. table.concat(paths, " | "))
		local abs_by_rel = {}
		for i, path in ipairs(paths) do abs_by_rel[path] = absolute[i] end
		local statuses = {}
		for _, path in ipairs(paths) do statuses[path] = State.status_of(root, path) end
		local kept, excluded = Targets.exclude_untracked(paths, statuses)
		trace("discard:kept=" .. table.concat(kept, " | ") .. " excluded=" .. table.concat(excluded, " | "))
		if #excluded > 0 then Notify.warn("Untracked/ignored targets were excluded: " .. table.concat(excluded, ", ")) end
		if #kept == 0 then return end
		local recursive = false
		for _, path in ipairs(kept) do
			if info[abs_by_rel[path]] then recursive = true end
		end
		local body = "Discard local changes?\n\n" .. Targets.describe(kept)
		if recursive then
			local value, event = ya.input({ title = 'Type "revert" to confirm recursive discard:', pos = { "center", w = 50 } })
			if event ~= 1 or value ~= (cfg.discard.recursive_confirm_text or "revert") then return Notify.info("Discard cancelled.") end
		elseif cfg.discard.confirm then
			local value, event = ya.input({
				title = 'Type "discard" to confirm:\n' .. body,
				pos = { "center", w = 60 },
			})
			if event ~= 1 or value ~= "discard" then return Notify.info("Discard cancelled.") end
		end
		local fallback = kind == "git" and Commands.git_discard(kept) or Commands.svn_discard(kept, recursive)
		trace("discard:run command=" .. kind .. " args=" .. table.concat(fallback, " | "))
		local output, err = run(root, kind, fallback, cfg)
		trace("discard:run-result=" .. tostring(output and output.status and output.status.success) .. " error=" .. tostring(err))
		local operation = kind:gsub("^%l", string.upper) .. " discard"
		if not output or not output.status.success then return failure(operation, output, err) end
		finish(root, operation, output)
	end)
end

local function named_external(args)
	return args and (args.external == true or args.external == "true" or args[2] == "--external") or false
end

function M.entry(action, args)
	local handlers = {
		update = M.update,
		commit = M.commit,
		diff = function() return M.diff(named_external(args)) end,
		log = function() return M.log(named_external(args)) end,
		discard = M.discard,
	}
	if handlers[action] then return handlers[action]() end
	Notify.warn("Unknown action: %s", tostring(action))
end

return M
