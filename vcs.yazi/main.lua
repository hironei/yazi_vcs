--- @since 26.5.6
-- main.lua
-- Fetcher/status display plus Phase 2, Phase 3, and Phase 4 actions.
local Config = require(".config")
local Context = require(".core-context")
local Detector = require(".core-detector")
local FileStatus = require(".core-status")
local State = require(".core-state")
local Notify = require(".core-notify")
local Path = require(".core-path")
local Runner = require(".core-runner")
local Targets = require(".core-targets")
local Actions = require(".actions")
local GitActions = require(".git-actions")
local VcsInfo = require(".core-vcs-info")

local BACKENDS = { git = require(".backend-git"), svn = require(".backend-svn") }
local M = {}

local function fetch_vcs_info(kind, root, cfg)
	local backend = BACKENDS[kind]
	if kind == "git" then
		local output = Runner.run(backend.info_spec(root), cfg.runner.timeout_ms)
		if output and output.status.success then
			return { kind = kind, data = backend.parse_info(output.stdout) }
		end
	elseif kind == "svn" then
		local url_output = Runner.run(backend.info_spec(root), cfg.runner.timeout_ms)
		if url_output and url_output.status.success then
			return { kind = kind, data = backend.parse_info(url_output.stdout) }
		end
	end
	return nil
end

function M:setup(opts)
	if opts == nil and type(self) == "table" and self ~= M then opts = self end
	Config.setup(opts)
	local cfg = Config.get()
	if type(cfg.info) == "table" and cfg.info.enabled then
		Status:children_add(function()
			local root = State.root_of(tostring(cx.active.current.cwd))
			if not root then return "" end
			local record = State.info_of(root)
			local kind, info = record and record.kind, record and record.data
			local hovered = cx.active.current.hovered
			local target = hovered and tostring(hovered.url) or tostring(cx.active.current.cwd)
			local relpath = kind == "svn" and Path.strip_prefix(root, target) or nil
			if kind == "svn" and not relpath then return "" end
			local label = VcsInfo.format(kind, info, relpath)
			if not label then return "" end
			return ui.Line { " ", ui.Span(label):fg(kind == "git" and "blue" or "yellow"), " " }
		end, cfg.info.order, Status.RIGHT)
	end
	Linemode:children_add(function(self)
		if not self._file.in_current then return "" end
		local root = State.root_of(tostring(self._file.url.base or self._file.url.parent))
		if not root then return "" end
		local rel = Path.strip_prefix(root, tostring(self._file.url))
		local name = FileStatus.display_name(rel and State.status_of(root, rel) or nil)
		if not name or name == "clean" then return "" end
		local sign = cfg.signs[name]
		if not sign or sign == "" then return "" end
		if self._file.is_hovered then return ui.Line { sign, " " } end
		local sty = th.vcs and th.vcs[name]
		return sty and ui.Line { ui.Span(sign):style(sty), " " } or ui.Line { sign, " " }
	end, cfg.status.order)
end

---@type UnstableFetcher
function M:fetch(job)
	if not job.files or #job.files == 0 then return true end
	local cwd = job.files[1].url.base or job.files[1].url.parent
	local cwd_str, cfg = tostring(cwd), Config.get()
	local kind, root = Detector.detect(cwd, cfg.detection.priority)
	if not kind then State.forget(cwd_str); return true end
	local root_str, queried, seen = root, {}, {}
	for _, file in ipairs(job.files) do
		local rel = Path.strip_prefix(root_str, tostring(file.url))
		if rel and not seen[rel] then
			seen[rel] = true
			queried[#queried + 1] = rel
		end
	end
	local backend = BACKENDS[kind]
	local output, err = Runner.run(backend.status_spec(root_str, queried, { ignore_externals = cfg.status.ignore_externals }), cfg.runner.timeout_ms)
	if not output then return true, Err("Cannot run `%s status`: %s", kind, err) end
	if not output.status.success then
		return true, Err("Cannot run `%s status`: %s", kind, Runner.error_text(output, err))
	end
	local changed, excluded = backend.parse_status_output(output.stdout)
	if cfg.status.aggregate_directories then FileStatus.merge(changed, FileStatus.bubble_up(changed)) end
	local cwd_rel = Path.strip_prefix(root_str, cwd_str) or ""
	FileStatus.merge(changed, FileStatus.propagate_down(excluded, cwd_rel))
	for _, rel in ipairs(queried) do if changed[rel] == nil then changed[rel] = "clean" end end
	-- Refresh repository metadata together with status. The branch or SVN
	-- location may have changed outside Yazi since the previous fetch.
	local vcs_info = fetch_vcs_info(kind, root_str, cfg)
	State.remember(cwd_str, root_str, changed, vcs_info)
	return false
end

function M:entry(job)
	local action = job.args[1]
	if action == "status" then return M.refresh_status() end
	if action == "push" or action == "branch" or action == "switch" then return GitActions.entry(action, job.args) end
	return Actions.entry(action, job.args)
end

function M.refresh_status()
	local cfg = Config.get()
	local context = Context.snapshot()
	local scope, reason = Targets.resolve(context.selected, context.cwd, context.info, function(start)
		return Detector.detect(Url(start), cfg.detection.priority)
	end)
	if not scope then
		if reason and reason.code == "mixed" then
			return Notify.error("Selected targets do not belong to the same Git or SVN working copy.")
		end
		return Notify.warn("Not inside a Git or SVN working copy.")
	end
	local root = scope.root
	State.clear_root(root)
	ya.emit("refresh", {})
	Notify.info("VCS status refreshed.")
end

return M
