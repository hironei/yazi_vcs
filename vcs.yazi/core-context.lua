-- core-context.lua
-- Capture one immutable-looking Yazi context snapshot per VCS operation.
--
-- `resolve_url` and `build_snapshot` are pure (no Yazi API calls) and are
-- exercised directly by the unit tests. Yazi-facing wrappers capture state
-- synchronously, then complete missing metadata in their async callers.
local M = {}

local function field(value, key)
	if value == nil then return nil end
	local ok, result = pcall(function() return value[key] end)
	if ok then return result end
end

local function directory_flag(entry)
	local value = field(field(entry, "cha"), "is_dir")
	if type(value) == "boolean" then return value end
end

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
	for i = 1, #current_files do
		local file = current_files[i]
		local path = file and M.resolve_url(file)
		if path then info[path] = directory_flag(file) end
	end
	for _, entry in pairs(selected_entries) do
		local path = M.resolve_url(entry)
		if path then
			selected[#selected + 1] = path
			local is_dir = directory_flag(entry)
			if is_dir ~= nil then info[path] = is_dir end
		end
	end
	return { selected = selected, cwd = cwd, info = info, search = search == true }
end

local function file_source(entry)
	local path = M.resolve_url(entry)
	if not path then return nil end
	return {
		path = path,
		-- Preserve unknown until the async wrapper can inspect the filesystem.
		is_dir = directory_flag(entry),
		search = M.is_search(entry),
	}
end

--- Capture plain filesystem-item records from Yazi's selected/hovered values.
---@param entries table
---@return table[]
function M.build_file_sources(entries)
	local sources = {}
	for _, entry in pairs(entries or {}) do
		local source = file_source(entry)
		if source then sources[#sources + 1] = source end
	end
	table.sort(sources, function(left, right) return left.path < right.path end)
	return sources
end

--- The split-tabs plugin presents exactly two manager tabs as its panes.
---@param tab_count integer
---@param active_index integer
---@return integer? other_index
function M.other_tab_index(tab_count, active_index)
	if tab_count ~= 2 then return nil end
	if active_index == 1 then return 2 end
	if active_index == 2 then return 1 end
	return nil
end

--- Build an action snapshot without retaining Yazi-owned Url/File values.
---@param selected_entries table
---@param hovered_entry any?
---@param active_cwd any
---@param tabs table
---@param active_index integer
---@return table
function M.build_file_operation_context(selected_entries, hovered_entry, active_cwd, tabs, active_index)
	local selected = M.build_file_sources(selected_entries)
	local hovered = file_source(hovered_entry)
	local other_index = M.other_tab_index(#tabs, active_index)
	local other = other_index and tabs[other_index] or nil
	local other_current = other and other.current or nil
	local other_cwd = field(other_current, "cwd")
	return {
		selected = selected,
		hovered = hovered,
		active_cwd = M.resolve_url(active_cwd),
		active_search = M.is_search(active_cwd),
		tab_count = #tabs,
		other_index = other_index,
		other_cwd = M.resolve_url(other_cwd),
		other_search = M.is_search(other_cwd),
	}
end

local capture_snapshot = ya.sync(function()
	local tab = cx.active
	local cwd = tab.current.cwd
	return M.build_snapshot(tab.selected, tab.current.files, M.resolve_url(cwd), M.is_search(cwd))
end)

local capture_file_operation_snapshot = ya.sync(function()
	local active = cx.active
	return M.build_file_operation_context(
		active.selected,
		active.current.hovered,
		active.current.cwd,
		cx.tabs,
		cx.tabs.idx
	)
end)

-- fs.cha is async-only. Capture plain paths/booleans in ya.sync first,
-- then resolve incomplete metadata after returning to the async caller.
local function directory_on_disk(path)
	local ok, cha = pcall(function() return fs.cha(Url(path), true) end)
	-- Preserve the previous non-directory fallback for vanished/unreadable
	-- paths. File actions still perform their own existence check before use.
	return ok and field(cha, "is_dir") == true
end

function M.snapshot()
	local snapshot = capture_snapshot()
	for _, path in ipairs(snapshot.selected) do
		if snapshot.info[path] == nil then snapshot.info[path] = directory_on_disk(path) end
	end
	return snapshot
end

function M.file_operation_snapshot()
	local snapshot = capture_file_operation_snapshot()
	local function complete(source)
		if source and source.is_dir == nil then source.is_dir = directory_on_disk(source.path) end
	end
	for _, source in ipairs(snapshot.selected) do complete(source) end
	complete(snapshot.hovered)
	return snapshot
end

return M
