-- core-context.lua
-- Capture one immutable-looking Yazi context snapshot per VCS operation.
--
-- `resolve_url` and `build_snapshot` are pure (no Yazi API calls) and are
-- exercised directly by the unit tests. `M.snapshot` is the Yazi-facing
-- `ya.sync` wrapper and is exercised only inside Yazi itself.
local M = {}

--- Resolve one `pairs(tab.selected)` entry to its `Url`-like value.
--- Yazi 26.8.15 changed this entry from a `Url` (26.5.6) to a `File`, which
--- carries the url under `.url`; a plain `Url` has no such field, so it
--- falls through to itself. No version branching is needed.
---@param entry any
---@return any
function M.resolve_url(entry)
	return entry.url or entry
end

--- Build the snapshot tables from already-extracted selected entries and
--- current-file list.
---@param selected_entries table  the values `pairs(tab.selected)` yields (File- or Url-shaped)
---@param current_files table     `tab.current.files`-shaped list ({ url, cha } entries)
---@param cwd string              `tostring(tab.current.cwd)`
---@return table snapshot { selected, cwd, info }
function M.build_snapshot(selected_entries, current_files, cwd)
	local selected, info = {}, {}
	for _, entry in pairs(selected_entries) do
		local path = tostring(M.resolve_url(entry))
		selected[#selected + 1] = path
		info[path] = false
	end
	for i = 1, #current_files do
		local file = current_files[i]
		if file then info[tostring(file.url)] = file.cha and file.cha.is_dir or false end
	end
	return { selected = selected, cwd = cwd, info = info }
end

M.snapshot = ya.sync(function()
	local tab = cx.active
	return M.build_snapshot(tab.selected, tab.current.files, tostring(tab.current.cwd))
end)

return M
