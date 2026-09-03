-- core-state.lua
-- Persistent state shared through Yazi's sync context.
local status = require(".core-status")
local M = {}

M.set_config = ya.sync(function(state, cfg)
	state.config = cfg
end)

M.get_config = ya.sync(function(state)
	return state.config
end)

M.set_vcs_spotter = ya.sync(function(state, id)
	state.vcs_spotter_id = id
	state.vcs_spot_active = true
end)

M.get_vcs_spotter = ya.sync(function(state)
	return state.vcs_spotter_id
end)

M.clear_vcs_spotter = ya.sync(function(state)
	state.vcs_spotter_id = nil
end)

M.set_vcs_spot_active = ya.sync(function(state, active)
	state.vcs_spot_active = active == true
end)

M.is_vcs_spot_active = ya.sync(function(state)
	return state.vcs_spot_active == true
end)

M.remember = ya.sync(function(state, cwd, root, changed, vcs_info)
	state.dirs = state.dirs or {}
	state.roots = state.roots or {}
	state.vcs_info = state.vcs_info or {}
	state.dirs[cwd] = root
	state.roots[root] = state.roots[root] or {}
	-- A Changes View seeds status before metadata is necessarily available.
	-- Preserve an already fetched branch/URL record when no new metadata exists.
	state.vcs_info[root] = vcs_info or state.vcs_info[root]
	status.merge(state.roots[root], changed)
	ui.render()
end)

M.replace = ya.sync(function(state, cwd, root, changed, vcs_info)
	state.dirs = state.dirs or {}
	state.roots = state.roots or {}
	state.vcs_info = state.vcs_info or {}
	state.dirs[cwd] = root
	state.roots[root] = {}
	state.vcs_info[root] = vcs_info or state.vcs_info[root]
	status.merge(state.roots[root], changed or {})
	ui.render()
end)

M.forget = ya.sync(function(state, cwd)
	state.dirs = state.dirs or {}
	if not state.dirs[cwd] then
		return
	end
	local root = state.dirs[cwd]
	state.dirs[cwd] = nil
	state.roots = state.roots or {}
	state.vcs_info = state.vcs_info or {}
	for _, remembered_root in pairs(state.dirs) do
		if remembered_root == root then
			ui.render()
			return
		end
	end
	state.roots[root] = nil
	state.vcs_info[root] = nil
	ui.render()
end)

M.clear_root = ya.sync(function(state, root)
	state.roots = state.roots or {}
	state.vcs_info = state.vcs_info or {}
	state.roots[root] = nil
	state.vcs_info[root] = nil
	ui.render()
end)

M.begin_action = ya.sync(function(state, root)
	state.actions = state.actions or {}
	if state.actions[root] then
		return false
	end
	state.actions[root] = true
	return true
end)

M.end_action = ya.sync(function(state, root)
	state.actions = state.actions or {}
	state.actions[root] = nil
end)

M.root_of = ya.sync(function(state, cwd)
	state.dirs = state.dirs or {}
	return state.dirs[cwd]
end)

M.status_of = ya.sync(function(state, root, relpath)
	state.roots = state.roots or {}
	local bucket = state.roots[root]
	return bucket and bucket[relpath] or nil
end)

M.info_of = ya.sync(function(state, root)
	state.vcs_info = state.vcs_info or {}
	return state.vcs_info[root]
end)

return M
