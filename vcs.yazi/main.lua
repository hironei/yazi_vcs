--- @since 26.5.6
-- main.lua
-- Fetcher/status display plus Phase 2 common VCS actions.
local Config = require(".config")
local Detector = require(".core-detector")
local Status = require(".core-status")
local State = require(".core-state")
local Notify = require(".core-notify")
local Path = require(".core-path")
local Actions = require(".actions")

local BACKENDS = {
	git = require(".backend-git"),
	svn = require(".backend-svn"),
}

local M = {}

function M:setup(opts)
	if opts == nil and type(self) == "table" and self ~= M then
		opts = self
	end
	Config.setup(opts)
	local cfg = Config.get()

	Entity:children_add(function(entity)
		if not entity._file.in_current then
			return ""
		end
		local root = State.root_of(tostring(entity._file.url.base or entity._file.url.parent))
		if not root then
			return ""
		end
		local rel = Path.strip_prefix(root, tostring(entity._file.url))
		local name = rel and State.status_of(root, rel) or nil
		name = Status.display_name(name)
		if not name or name == "clean" then
			return ""
		end
		local sign = cfg.signs[name]
		if not sign or sign == "" then
			return ""
		end
		if entity._file.is_hovered then
			return ui.Line { sign, " " }
		end
		local sty = th.vcs and th.vcs[name]
		return sty and ui.Line { ui.Span(sign):style(sty), " " } or ui.Line { sign, " " }
	end, cfg.status.order)
end

---@type UnstableFetcher
function M:fetch(job)
	if not job.files or #job.files == 0 then
		return true
	end
	local cwd = job.files[1].url.base or job.files[1].url.parent
	local cwd_str = tostring(cwd)
	local cfg = Config.get()
	local kind, root = Detector.detect(cwd, cfg.detection.priority)
	if not kind then
		State.forget(cwd_str)
		return true
	end
	local root_str = tostring(root)
	local queried = {}
	for _, file in ipairs(job.files) do
		local rel = Path.strip_prefix(root_str, tostring(file.url))
		if rel then
			queried[#queried + 1] = rel
		end
	end
	local changed, excluded, err = BACKENDS[kind].fetch(root_str, queried, {
		ignore_externals = cfg.status.ignore_externals,
	})
	if err then
		return true, Err("Cannot run `%s status`: %s", kind, err)
	end
	if cfg.status.aggregate_directories then
		Status.merge(changed, Status.bubble_up(changed))
	end
	local cwd_rel = Path.strip_prefix(root_str, cwd_str) or ""
	Status.merge(changed, Status.propagate_down(excluded, cwd_rel))
	for _, rel in ipairs(queried) do
		if changed[rel] == nil then
			changed[rel] = "clean"
		end
	end
	State.remember(cwd_str, root_str, changed)
	return false
end

function M:entry(job)
	local action = job.args[1]
	if action == "status" then
		return M.refresh_status()
	end
	return Actions.entry(action)
end

function M.refresh_status()
	local cwd = State.current_url()
	local cfg = Config.get()
	local _, detected_root = Detector.detect(cwd, cfg.detection.priority)
	local root = detected_root and tostring(detected_root) or State.root_of(tostring(cwd))
	if not root then
		Notify.warn("Not inside a Git or SVN working copy.")
		return
	end
	State.clear_root(root)
	ya.emit("refresh", {})
	Notify.info("VCS status refreshed.")
end

return M
