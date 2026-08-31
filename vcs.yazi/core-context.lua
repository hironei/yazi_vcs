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
	local url
	if type(entry) == "table" then
		url = entry.url or entry
	else
		local ok, value = pcall(function() return entry.url end)
		url = ok and value or entry
	end
	if url == nil then return nil end
	local ok, path = pcall(function() return url.path end)
	if ok and path ~= nil then return tostring(path) end
	return tostring(url)
end

--- Whether a File or Url belongs to Yazi's Search View.
---@param entry any
---@return boolean
function M.is_search(entry)
	local url
	if type(entry) == "table" then
		url = entry.url or entry
	else
		local ok, value = pcall(function() return entry.url end)
		url = ok and value or entry
	end
	if url == nil then return false end
	local ok, spec = pcall(function() return url.spec end)
	if not ok or spec == nil then return false end
	local spec_ok, result = pcall(function() return spec.is_search end)
	return spec_ok and result == true
end

--- Build the snapshot tables from already-extracted selected entries and
--- current-file list.
---@param selected_entries table  the values `pairs(tab.selected)` yields (File- or Url-shaped)
---@param current_files table     `tab.current.files`-shaped list ({ url, cha } entries)
---@param cwd string              `tostring(tab.current.cwd)`
---@param search boolean?       whether the current cwd is a Search View URL
---@return table snapshot { selected, cwd, info, search }
function M.build_snapshot(selected_entries, current_files, cwd, search)
	local selected, info = {}, {}
	for _, entry in pairs(selected_entries) do
		local path = M.resolve_url(entry)
		selected[#selected + 1] = path
		info[path] = false
	end
	for i = 1, #current_files do
		local file = current_files[i]
		local path = file and M.resolve_url(file.url)
		if path then info[path] = file.cha and file.cha.is_dir or false end
	end
	return { selected = selected, cwd = cwd, info = info, search = search == true }
end

M.snapshot = ya.sync(function()
	local tab = cx.active
	local cwd = tab.current.cwd
	return M.build_snapshot(tab.selected, tab.current.files, M.resolve_url(cwd), M.is_search(cwd))
end)

return M
