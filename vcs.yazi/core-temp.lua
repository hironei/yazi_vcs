-- core-temp.lua
-- Temporary-path generation shared by actions and tests. `os.tmpname()` can
-- return an unusable pseudo-UNC path on Windows, so use the platform temp
-- directory and a process-local unique suffix instead.
local M = {}
local counter = 0
local is_windows = package.config:sub(1, 1) == "\\"

local function temp_root()
	if is_windows then
		return os.getenv("TEMP") or os.getenv("TMP") or "."
	end
	return os.getenv("TMPDIR") or os.getenv("TEMP") or os.getenv("TMP") or "/tmp"
end

local function trim_separator(path)
	local trimmed = path:gsub("[/\\]+$", "")
	return trimmed == "" and path or trimmed
end

--- Return an unused path in the platform temporary directory.
---@param prefix string|nil
---@param extension string|nil including the leading dot
---@return string|nil path
---@return string|nil err
function M.path(prefix, extension)
	local root = trim_separator(tostring(temp_root()))
	prefix = tostring(prefix or "vcs")
	extension = extension or ".tmp"
	for _ = 1, 100 do
		counter = counter + 1
		local path = string.format("%s%s%s-%d-%d%s", root, is_windows and "\\" or "/", prefix, os.time(), counter, extension)
		local file = io.open(path, "r")
		if file then
			file:close()
		else
			return path
		end
	end
	return nil, "could not allocate a unique temporary path"
end

return M
