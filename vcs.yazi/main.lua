--- @since 26.5.6
-- main.lua
-- Entry point: fetcher registration, leading-column status sign
-- rendering, `setup`, and the manual-refresh keymap action.
--
-- Phase 1 scope (requirements §29): Status MVP. See docs/requirements.md
-- for the full spec and the rationale behind each design choice
-- referenced below.
local Config = require(".config")
local Detector = require(".core-detector")
local Status = require(".core-status")
local State = require(".core-state")
local Notify = require(".core-notify")
local Path = require(".core-path")

local BACKENDS = {
	git = require(".backend-git"),
	svn = require(".backend-svn"),
}

local M = {}

--- Register the leading-column status sign (requirements §8.1) and
--- persist the merged configuration. Called synchronously by Yazi from
--- `~/.config/yazi/init.lua`'s `require("vcs"):setup{ ... }`.
---@param opts table|nil
function M:setup(opts)
	if opts == nil and type(self) == "table" and self ~= M then
		opts = self
	end
	Config.setup(opts)
	local cfg = Config.get()

	Entity:children_add(function(entity)
		-- Mirrors the official `git.yazi` plugin's own guard: only
		-- render for the file's home listing, not other panes it might
		-- also appear in (e.g. preview).
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

		-- Hovered rows already have an inverted/highlighted background;
		-- render unstyled there so a custom foreground color doesn't
		-- clash with it, same as `git.yazi`.
		if entity._file.is_hovered then
			return ui.Line { sign, " " }
		end

		local sty = th.vcs and th.vcs[name]
		return sty and ui.Line { ui.Span(sign):style(sty), " " } or ui.Line { sign, " " }
	end, cfg.status.order)
end

--- Fetch VCS status for `job.files` (requirements §8.7). Registered as
--- a `[[plugin.prepend_fetchers]]` target in the user's `yazi.toml` —
--- see README.md.
---@type UnstableFetcher
function M:fetch(job)
	local cwd = job.files[1].url.base or job.files[1].url.parent
	local cwd_str = tostring(cwd)
	local cfg = Config.get()

	local kind, root = Detector.detect(cwd, cfg.detection.priority)
	if not kind then
		State.forget(cwd_str)
		return true
	end
	local root_str = tostring(root)

	-- Targets must be root-relative, forward-slash paths: verified
	-- empirically that SVN (unlike Git) echoes each target back in its
	-- XML output exactly as given, so an absolute input path would
	-- break the root-relative-key assumption both backends rely on.
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

	-- Roll file-level changes up onto the ancestor directories being
	-- listed, when what's being fetched is itself directory rows
	-- (requirements §8.6).
	if cfg.status.aggregate_directories and job.files[1].cha.is_dir then
		Status.merge(changed, Status.bubble_up(changed))
	end

	-- Git-only: a wholly-ignored directory is reported once, without its
	-- contents (requirements §8.4); this reconciles that with `cwd`
	-- itself potentially being that directory or a direct parent of it.
	local cwd_rel = Path.strip_prefix(root_str, cwd_str) or ""
	Status.merge(changed, Status.propagate_down(excluded, cwd_rel))

	-- A path that stopped being modified since the last fetch simply
	-- disappears from the backend's output; reset it to "clean" instead
	-- of leaving a stale sign.
	for _, rel in ipairs(queried) do
		if changed[rel] == nil then
			changed[rel] = "clean"
		end
	end

	State.remember(cwd_str, root_str, changed)
	return false
end

--- Dispatch a `plugin vcs -- <action>` keymap invocation (requirements
--- §19). Phase 1 only implements manual status refresh (§9).
---@param job table
function M:entry(job)
	local action = job.args[1]
	if action == "status" then
		M.refresh_status()
	else
		Notify.warn("Unknown action: %s", tostring(action))
	end
end

--- Manual status refresh (requirements §9): discard the cached status
--- for the current directory's VCS root and ask Yazi to re-run its
--- fetchers.
function M.refresh_status()
	local cwd = State.current_cwd()
	local root = State.root_of(cwd)
	if not root then
		Notify.warn("Not inside a Git or SVN working copy.")
		return
	end
	State.clear_root(root)
	ya.emit("refresh", {})
	Notify.info("VCS status refreshed.")
end

return M
