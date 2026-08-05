--- @since 26.5.6
-- main.lua
-- Fetcher/status display plus Phase 2, Phase 3, and Phase 4 actions.
local Config = require(".config")
local Detector = require(".core-detector")
local Status = require(".core-status")
local State = require(".core-state")
local Notify = require(".core-notify")
local Path = require(".core-path")
local Runner = require(".core-runner")
local Actions = require(".actions")
local GitActions = require(".git-actions")

local BACKENDS = { git = require(".backend-git"), svn = require(".backend-svn") }
local M = {}

function M:setup(opts)
	if opts == nil and type(self) == "table" and self ~= M then opts = self end
	Config.setup(opts)
	local cfg = Config.get()
	Linemode:children_add(function(self)
		if not self._file.in_current then return "" end
		local root = State.root_of(tostring(self._file.url.base or self._file.url.parent))
		if not root then return "" end
		local rel = Path.strip_prefix(root, tostring(self._file.url))
		local name = Status.display_name(rel and State.status_of(root, rel) or nil)
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
	local output, err = Runner.output(backend.status_spec(root_str, queried, { ignore_externals = cfg.status.ignore_externals }))
	if not output then return true, Err("Cannot run `%s status`: %s", kind, err) end
	if not output.status.success then
		return true, Err("Cannot run `%s status`: %s", kind, Runner.error_text(output, err))
	end
	local changed, excluded = backend.parse_status_output(output.stdout)
	if cfg.status.aggregate_directories then Status.merge(changed, Status.bubble_up(changed)) end
	local cwd_rel = Path.strip_prefix(root_str, cwd_str) or ""
	Status.merge(changed, Status.propagate_down(excluded, cwd_rel))
	for _, rel in ipairs(queried) do if changed[rel] == nil then changed[rel] = "clean" end end
	State.remember(cwd_str, root_str, changed)
	return false
end

function M:entry(job)
	local action = job.args[1]
	if action == "status" then return M.refresh_status() end
	if action == "push" or action == "branch" or action == "switch" then return GitActions.entry(action, job.args) end
	return Actions.entry(action, job.args)
end

function M.refresh_status()
	local cwd, cfg = State.current_url(), Config.get()
	local _, detected_root = Detector.detect(cwd, cfg.detection.priority)
	local root = detected_root or State.root_of(tostring(cwd))
	if not root then return Notify.warn("Not inside a Git or SVN working copy.") end
	State.clear_root(root)
	ya.emit("refresh", {})
	Notify.info("VCS status refreshed.")
end

return M
