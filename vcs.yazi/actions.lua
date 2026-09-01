-- actions.lua
-- Phase 2 common VCS operations plus Phase 4 external viewers.
local Config = require(".config")
local Detector = require(".core-detector")
local External = require(".core-external")
local Notify = require(".core-notify")
local Path = require(".core-path")
local Runner = require(".core-runner")
local Scope = require(".core-scope")
local State = require(".core-state")
local Targets = require(".core-targets")
local Changes = require(".core-changes")
local LogPreview = require(".core-log-preview")
local Commands = require(".core-commands")
local Temp = require(".core-temp")
local GitBackend = require(".backend-git")
local SvnBackend = require(".backend-svn")
local VcsInfo = require(".core-vcs-info")

local M = {}

local current_hovered_url = ya.sync(function()
	local hovered = cx.active.current.hovered
	return hovered and hovered.url, hovered and hovered.cha and hovered.cha.is_dir == true
end)

local function trace(stage)
	if os.getenv("VCS_YAZI_TRACE") == "1" and type(ya.err) == "function" then
		ya.err("vcs trace: " .. stage)
	end
end

local function resolve_scope(cfg)
	return Scope.resolve_or_notify(cfg)
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

local function expand_template(template, paths, repository_scope)
	local expanded = {}
	local i = 1
	while i <= #(template or {}) do
		local token = template[i]
		if repository_scope and token == "--" and template[i + 1] == "{targets}" then
			i = i + 2
			goto continue
		end
		if token == "{targets}" then
			for _, path in ipairs(paths or {}) do expanded[#expanded + 1] = path end
		else
			expanded[#expanded + 1] = token
		end
		i = i + 1
		::continue::
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
	local ok, result = pcall(fn)
	State.end_action(root)
	if not ok then error(result, 0) end
	return result
end

local function finish_interactive(root, operation)
	State.clear_root(root)
	ya.emit("refresh", {})
	Notify.info("%s completed.", operation)
end

local function failure(operation, output, err)
	Notify.error("%s failed: %s", operation, Runner.error_text(output, err))
end

local function temp_file(content)
	local path, path_err = Temp.path("vcs-message")
	if not path then return nil, path_err end
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
	local temp_path, path_err = Temp.path("vcs-output")
	if not temp_path then return nil, path_err end
	local url = Url(temp_path)
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

local function external_context(root, absolute, cfg, spec, repository_scope)
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
	local file = absolute and absolute[1] and convert_external_path(absolute[1], style, environment, root, cfg) or root_path
	local targets = {}
	if not repository_scope then
		for _, path in ipairs(absolute or {}) do targets[#targets + 1] = convert_external_path(path, style, environment, root, cfg) end
	end
	return { root = root_path, file = file, targets = targets, revision = spec.revision or "" }
end

local function run_external(root, operation, spec, absolute, cfg, repository_scope)
	local valid, reason = External.validate(spec)
	if not valid then return Notify.error("%s is not configured: %s", operation, reason) end
	local context = external_context(root, absolute, cfg, spec, repository_scope)
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

local function has_diff(root, kind, paths, cfg)
	local args = kind == "git" and Commands.git_diff(paths) or Commands.svn_diff(paths)
	local output, err = Runner.run({ command = kind, args = args, cwd = root }, cfg.runner.timeout_ms)
	if not output or not output.status.success then return nil, output, err end
	return Runner.summary(output.stdout, 1) ~= "", output, nil
end

local function query_changed(root, kind, cfg)
	local backend = kind == "git" and GitBackend or SvnBackend
	local output, err = Runner.run(
		backend.status_spec(root, nil, { ignore_externals = cfg.status.ignore_externals }),
		cfg.runner.timeout_ms
	)
	if not output or not output.status.success then return nil, output, err end
	local changed = backend.parse_status_output(output.stdout)
	return changed, output, nil
end

local function display_output(operation, content, cfg)
	if Runner.summary(content, 1) == "" then return Notify.info("No output from %s.", operation) end
	local file, temp_err = temp_output_file(content)
	if not file then return Notify.error("Cannot create output file: %s", temp_err) end
	local shown, display_err = display_file(file, cfg)
	remove_output_file(file)
	if not shown then return Notify.error("%s output could not be displayed: %s", operation, display_err) end
end

--- Run a Git diff for selected Changes View entries. `git diff` does not
--- include untracked files, so each untracked file is compared with a shared
--- empty temporary file. Git's no-index exit code 1 means "differences found"
--- and is successful for this operation.
local function changed_git_diff(root, paths, statuses, cfg)
	local tracked, untracked = Changes.partition(paths, statuses)
	local chunks = {}
	if #tracked > 0 then
		local output, err = run(root, "git", Commands.git_diff(tracked), cfg)
		if not output or not output.status.success then return nil, output, err end
		if output.stdout and output.stdout ~= "" then chunks[#chunks + 1] = output.stdout end
	end
	if #untracked == 0 then return table.concat(chunks, "\n"), nil, nil end

	local empty_path, temp_err = temp_file("")
	if not empty_path then return nil, nil, temp_err end
	for _, path in ipairs(untracked) do
		local output, err = run(root, "git", Commands.git_diff_no_index(empty_path, path), cfg)
		local acceptable = output and (output.status.success or output.status.code == 1)
		if not acceptable then
			remove_file(empty_path)
			return nil, output, err
		end
		if output.stdout and output.stdout ~= "" then chunks[#chunks + 1] = output.stdout end
	end
	remove_file(empty_path)
	return table.concat(chunks, "\n"), nil, nil
end

function M.changes()
	local cfg = Config.get()
	local scope = resolve_scope(cfg)
	if not scope then return end
	local kind, root = scope.kind, scope.root
	with_lock(root, "Changes", function()
		local changed, output, err = query_changed(root, kind, cfg)
		if not changed then return failure("VCS changes status", output, err) end
		local entries = Changes.list(changed)
		if #entries == 0 then return Notify.info("No changed files.") end

		-- Seed the shared state so Linemode can draw status signs immediately.
		-- The fetcher will refresh this state again after the Search View opens.
		State.replace(root, root, changed, nil)
		local search_cwd = Url(root):into_search("VCS Changes")
		local id = ya.id("ft")
		ya.emit("cd", { Url(search_cwd), source = "search" })
		ya.emit("update_files", { op = fs.op("part", { id = id, url = Url(search_cwd), files = {} }) })

		local files = {}
		for _, entry in ipairs(entries) do
			local url = search_cwd:join(entry.path)
			-- Deleted/missing paths have no filesystem metadata. A synthetic
			-- regular-file Cha keeps them in Search View and selectable.
			local cha = fs.cha(url, true) or Cha { mode = tonumber("100644", 8) }
			files[#files + 1] = File { url = url, cha = cha }
		end
		local dir = File { url = search_cwd, cha = Cha { mode = tonumber("100644", 8) } }
		ya.emit("update_files", { op = fs.op("part", { id = id, url = dir.url, files = files }) })
		ya.emit("update_files", { op = fs.op("done", { id = id, file = dir }) })
	end, true)
end

function M.update()
	local cfg = Config.get()
	local scope = resolve_scope(cfg)
	if not scope then return end
	local kind, root = scope.kind, scope.root
	with_lock(root, "Update", function()
		local fallback = kind == "git" and Commands.git_update() or Commands.svn_update(nil)
		local command, args = argv(cfg.update and cfg.update[kind], kind, fallback)
		local operation = kind:gsub("^%l", string.upper) .. " update"
		local status, err = Runner.interactive({ command = command, args = args, cwd = root })
		if not status or not status.success then return failure(operation, status and { status = status } or nil, err) end
		finish_interactive(root, operation)
	end)
end

function M.add()
	local cfg = Config.get()
	local scope = resolve_scope(cfg)
	if not scope then return end
	local kind, root = scope.kind, scope.root
	with_lock(root, "Add", function()
		local paths = scope.paths
		if not paths or #paths == 0 then return Notify.warn("No VCS target selected.") end
		if not scope.explicit then
			local value, event = ya.input({
				title = 'Type "add" to confirm:\nAdd all applicable files under:\n\n' .. scope.absolute[1],
				pos = { "center", w = 60 },
			})
			if event ~= 1 or value ~= "add" then return Notify.info("Add cancelled.") end
		end
		local statuses = {}
		for _, path in ipairs(paths) do statuses[path] = State.status_of(root, path) end
		local kept, excluded = Targets.exclude_ignored(paths, statuses)
		if #excluded > 0 then Notify.warn("Ignored targets were excluded: " .. table.concat(excluded, ", ")) end
		if #kept == 0 then return end
		local fallback = kind == "git" and Commands.git_add(kept) or Commands.svn_add(kept)
		local output, err = run(root, kind, fallback, cfg)
		local operation = kind:gsub("^%l", string.upper) .. " add"
		if not output or not output.status.success then return failure(operation, output, err) end
		finish(root, operation, output)
	end)
end

function M.commit()
	local cfg = Config.get()
	local scope = resolve_scope(cfg)
	if not scope then return end
	local kind, root = scope.kind, scope.root
	with_lock(root, "Commit", function()
		local paths = scope.paths
		if not paths or #paths == 0 then return Notify.warn("No VCS target selected.") end
		local mode = kind == "git" and cfg.commit.git_mode or nil
		local body
		if scope.explicit then
			body = "Commit " .. #paths .. " target(s)?\n\n" .. Targets.describe(paths)
		else
			body = "Commit current directory scope:\n\n" .. scope.absolute[1]
			.. "\n\nThis may include multiple changed files under this directory."
			if scope.repository then body = body .. "\nThis is the repository root, so the scope includes the entire repository." end
		end
		if kind == "git" and mode ~= "staged" then body = body .. "\n\nSelected paths are staged implicitly by Git." end
		-- ya.confirm() does not render in the functional plugin task on
		-- Windows and leaves the task pending indefinitely (see issue #22,
		-- which hit the same problem in Discard); ya.input() is the
		-- confirmed-working alternative.
		local value, event = ya.input({ title = 'Type "commit" to confirm:\n' .. body, pos = { "center", w = 60 } })
		if event ~= 1 or value ~= "commit" then return Notify.info("Commit cancelled.") end
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
	local scope = resolve_scope(cfg)
	if not scope then return end
	local kind, root = scope.kind, scope.root
	with_lock(root, operation, function()
		local paths, absolute = scope.paths, scope.absolute
		if not paths then return end
		local command_paths = scope.repository and {} or paths
		local external_absolute = absolute
		local statuses
		if scope.search then
			statuses = {}
			for _, path in ipairs(paths) do statuses[path] = State.status_of(root, path) end
		end
		if not external and scope.search and config_section == "diff" and kind == "git" then
			local _, untracked = Changes.partition(paths, statuses)
			if #untracked > 0 then
				local content, output, err = changed_git_diff(root, paths, statuses, cfg)
				if content == nil then return failure(operation, output, err) end
				return display_output(operation, content, cfg)
			end
		end
		if scope.search and config_section == "log" and kind == "git" then
			local tracked, untracked = Changes.partition(paths, statuses)
			if #untracked > 0 then Notify.warn("Untracked files have no history: " .. table.concat(untracked, ", ")) end
			if #tracked == 0 then return Notify.info("No history for selected files.") end
			command_paths = tracked
			external_absolute = {}
			for index, path in ipairs(paths) do
				if statuses[path] ~= "untracked" then external_absolute[#external_absolute + 1] = absolute[index] end
			end
		elseif scope.search and config_section == "diff" and kind == "git" then
			local tracked, untracked = Changes.partition(paths, statuses)
			if #untracked > 0 then
				if #tracked == 0 then return Notify.info("External Diff cannot display untracked-only selections.") end
				Notify.warn("Untracked files were excluded from external Diff: " .. table.concat(untracked, ", "))
				command_paths = tracked
				external_absolute = {}
				for index, path in ipairs(paths) do
					if statuses[path] ~= "untracked" then external_absolute[#external_absolute + 1] = absolute[index] end
				end
			end
		end
		local section = cfg[config_section] or {}
		if external then
			if config_section == "diff" then
				local changed, output, err = has_diff(root, kind, command_paths, cfg)
				if changed == nil then return failure(operation .. " check", output, err) end
				if not changed then return Notify.info("%s: no differences for the selected scope.", operation) end
			end
			return run_external(root, operation .. " (external)", section[kind .. "_external"], external_absolute, cfg, scope.repository)
		end
		local configured = section[kind .. "_cli"]
		if scope.repository and config_section == "log" and kind == "git" and section.git_cli_all then
			configured = section.git_cli_all
		end
		local fallback = kind_builder(kind, command_paths)
		local command, args
		if configured then
			command, args = argv(configured, kind, fallback)
			args = expand_template(args, command_paths, scope.repository)
		else
			command, args = kind, fallback
		end
		local output, err = Runner.run({ command = command, args = args, cwd = root }, cfg.runner.timeout_ms)
		if not output or not output.status.success then return failure(operation, output, err) end
		if Runner.summary(output.stdout, 1) == "" then return Notify.info("No output from %s.", operation) end
		display_output(operation, output.stdout, cfg)
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

function M.log_preview()
	local hovered_url, is_dir = current_hovered_url()
	if not hovered_url then return Notify.warn("No hovered item to preview.") end

	local cfg = Config.get()
	local path = tostring(hovered_url)
	local start = is_dir and path or Path.parent(path)
	local root = State.root_of(start)
	local record = root and State.info_of(root)
	local kind = record and record.kind
	if not kind or not root then kind, root = Detector.detect(Url(start), cfg.detection.priority) end

	local lines = { "VCS log (latest 5)" }
	if not kind or not root then
		lines[#lines + 1] = LogPreview.message(nil, "outside-repository")
	else
		local relative = Path.strip_prefix(root, path)
		if not relative then
			lines[#lines + 1] = LogPreview.message(nil, "outside-root")
		elseif State.status_of(root, relative) == "untracked" then
			lines[#lines + 1] = LogPreview.message(nil, "untracked")
		else
			local args = LogPreview.args(kind, relative)
			local output, err = Runner.run({ command = kind, args = args, cwd = root }, cfg.runner.timeout_ms)
			if not output or not output.status.success then
				local detail = Runner.error_text(output, err):gsub("[\r\n]+", " ")
				lines[#lines + 1] = LogPreview.message(kind, "command-failed", detail)
			else
				local entries = LogPreview.parse(kind, output.stdout)
				if #entries == 0 then
					lines[#lines + 1] = LogPreview.message(nil, "empty")
				else
					for _, entry in ipairs(entries) do lines[#lines + 1] = entry end
				end
			end
		end
	end

	Notify.history(table.concat(lines, "\n"))
end

function M.discard()
	local cfg = Config.get()
	local scope = resolve_scope(cfg)
	if not scope then return end
	local kind, root = scope.kind, scope.root
	trace("discard:start kind=" .. kind .. " root=" .. tostring(root))
	with_lock(root, "Discard", function()
		local paths, info, absolute = scope.paths, scope.info, scope.absolute
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
			if not scope.explicit or info[abs_by_rel[path]] then recursive = true end
		end
		local body
		if scope.explicit then
			body = "Discard local changes?\n\n" .. Targets.describe(kept)
		else
			body = "Recursively discard local changes under:\n\n" .. scope.absolute[1]
			.. "\n\nThis operation cannot be undone."
		end
		if recursive then
			local value, event = ya.input({ title = 'Type "revert" to confirm:\n' .. body, pos = { "center", w = 60 } })
			if event ~= 1 or value ~= (cfg.discard.recursive_confirm_text or "revert") then return Notify.info("Discard cancelled.") end
		else
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

local function output_value(output)
	return tostring(output and output.stdout or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function copy_action(with_revision)
	local cfg = Config.get()
	local scope = resolve_scope(cfg)
	if not scope then return end
	local kind, root = scope.kind, scope.root

	local relative, absolute = scope.paths, scope.absolute
	if not relative or #relative == 0 then return Notify.warn("No VCS target selected.") end
	local relpath, target = relative[1], absolute[1]
	local record = State.info_of(root)
	if not record or record.kind ~= kind or not record.data then
		return Notify.error("Cannot copy VCS URL: repository metadata is not available yet.")
	end

	local info = record.data
	local value
	if kind == "svn" then
		value = VcsInfo.svn_target_url(info.url, relpath)
	else
		value = VcsInfo.git_target(info.branch, relpath)
	end
	if not value or value == "" then return Notify.error("Cannot copy VCS URL: metadata is incomplete.") end

	if with_revision then
		local output, err
		if kind == "svn" then
			output, err = Runner.run(SvnBackend.revision_spec(root, relpath), cfg.runner.timeout_ms)
		else
			output, err = Runner.run(GitBackend.revision_spec(root), cfg.runner.timeout_ms)
		end
		if not output or not output.status.success then
			return Notify.error("Copy URL with revision failed: %s", Runner.error_text(output, err))
		end
		local revision = output_value(output)
		if revision == "" then return Notify.error("Copy URL with revision failed: no revision was returned.") end
		value = value .. "@" .. revision
	end

	ya.clipboard(value)
	Notify.info("Copied to clipboard: %s", value)
	return target
end

function M.copy_url()
	return copy_action(false)
end

function M.copy_url_revision()
	return copy_action(true)
end

local function named_external(args)
	return args and (args.external == true or args.external == "true" or args[2] == "--external") or false
end

function M.entry(action, args)
	local handlers = {
		update = M.update,
		changes = M.changes,
		add = M.add,
		commit = M.commit,
		diff = function() return M.diff(named_external(args)) end,
		log = function() return M.log(named_external(args)) end,
		["log-preview"] = M.log_preview,
		discard = M.discard,
		["copy-url"] = M.copy_url,
		["copy-url-revision"] = M.copy_url_revision,
	}
	if handlers[action] then return handlers[action]() end
	Notify.warn("Unknown action: %s", tostring(action))
end

return M
