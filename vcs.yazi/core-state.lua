-- core-state.lua
-- Persistent, cross-context status storage (requirements §5.5, §8.7.3).
--
-- Every function here is wrapped in `ya.sync`, which is only available
-- inside a running Yazi plugin — this file cannot be `require`d under a
-- plain `lua` interpreter (unlike `core-status.lua`, which holds the
-- pure logic this module is built on and is what the unit tests exercise
-- directly). `ya.sync` binds its first argument to this module's own
-- table, shared by every caller regardless of which file they're defined
-- in, so it doubles as the storage itself.
local status = require(".core-status")

local M = {}

--- Store the merged configuration (built by `config.lua`, which cannot
--- hold this itself — see the note at the top of that file).
---@param cfg table
M.set_config = ya.sync(function(state, cfg)
	state.config = cfg
end)

--- The active configuration, or nil before `setup()` has run.
---@return table?
M.get_config = ya.sync(function(state)
	return state.config
end)

--- Merge a fetch's `changed` into the stored status for `root`, remember
--- that `cwd` belongs to `root`, and request a redraw. Callers are
--- responsible for having already backfilled "clean" for any queried
--- path absent from `changed` (see `git.yazi`'s equivalent step, ported
--- in `main.lua`'s `fetch`) — this function only merges what it is
--- given.
---@param cwd string
---@param root string
---@param changed table<string,string>
M.remember = ya.sync(function(state, cwd, root, changed)
	state.dirs = state.dirs or {}
	state.roots = state.roots or {}
	state.dirs[cwd] = root
	state.roots[root] = state.roots[root] or {}
	status.merge(state.roots[root], changed)
	ui.render()
end)

--- Forget that `cwd` belongs to a VCS root (a fetch found no root
--- there). Drops the root's stored status too once no remembered
--- directory references it anymore.
---@param cwd string
M.forget = ya.sync(function(state, cwd)
	state.dirs = state.dirs or {}
	if not state.dirs[cwd] then
		return
	end
	local root = state.dirs[cwd]
	state.dirs[cwd] = nil
	ui.render()

	state.roots = state.roots or {}
	for _, r in pairs(state.dirs) do
		if r == root then
			return
		end
	end
	state.roots[root] = nil
end)

--- Discard all remembered status for `root` (requirements §9; later
--- phases also call this after Commit/Update/Discard/Switch).
---@param root string
M.clear_root = ya.sync(function(state, root)
	state.roots = state.roots or {}
	state.roots[root] = nil
	ui.render()
end)

--- The active tab's current directory, read from `cx` (only safe from
--- sync context — `ya.sync` bridges async callers, mirroring the
--- official `zoxide.lua` preset plugin's own `cx.active.current.cwd`
--- access pattern).
---@return Url
M.current_url = ya.sync(function()
	return cx.active.current.cwd
end)

M.current_cwd = ya.sync(function()
	return tostring(cx.active.current.cwd)
end)

--- The VCS root remembered for directory `cwd`, or nil.
---@param cwd string
---@return string?
M.root_of = ya.sync(function(state, cwd)
	state.dirs = state.dirs or {}
	return state.dirs[cwd]
end)

--- The status name remembered for `relpath` within `root`, or nil
--- (render code should treat nil as "clean").
---@param root string
---@param relpath string
---@return string?
M.status_of = ya.sync(function(state, root, relpath)
	state.roots = state.roots or {}
	local bucket = state.roots[root]
	return bucket and bucket[relpath] or nil
end)

return M
