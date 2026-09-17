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

--- Return a collision-resistant candidate path in the platform temporary directory.
---@param prefix string|nil
---@param extension string|nil including the leading dot
---@return string|nil path
---@return string|nil err
function M.path(prefix, extension)
	local root = trim_separator(tostring(temp_root()))
	prefix = tostring(prefix or "vcs")
	extension = extension or ".tmp"
	counter = counter + 1
	local clock = math.floor((os.clock() % 1) * 1000000)
	local random = math.random(0, 0x7fffffff)
	return string.format("%s%s%s-%08x-%08x-%d%s", root, is_windows and "\\" or "/", prefix, clock, random, counter, extension)
end

function M.write(path, content)
	local unique, unique_err = fs.unique("file", Url(path))
	if not unique then return nil, unique_err or "could not allocate a unique temporary file" end
	local ok, write_err = fs.write(unique, content or "")
	if not ok then
		fs.remove("file", unique)
		return nil, write_err
	end
	return tostring(unique)
end

function M.remove(path)
	if not path then return true end
	return fs.remove("file", Url(path))
end

function M.display(content, cfg, runner)
	local path, err = M.path("vcs-output")
	if not path then return nil, err end
	local written_path, write_err = M.write(path, content)
	if not written_path then return nil, write_err end
	local viewer = cfg.pager and cfg.pager.command and cfg.pager.command ~= "" and cfg.pager or cfg.editor
	if not viewer or not viewer.command or viewer.command == "" then
		M.remove(written_path)
		return nil, "pager/editor is not configured"
	end
	local args = {}
	for _, value in ipairs(viewer.args or {}) do args[#args + 1] = value end
	args[#args + 1] = written_path
	local audit_config = cfg.runner and cfg.runner.audit
	local status, command_err = runner.interactive({ command = viewer.command, args = args }, audit_config)
	local removed, remove_err = M.remove(written_path)
	if not status then return nil, command_err end
	if not status.success then return nil, "viewer exited with code " .. tostring(status.code or "unknown") end
	if removed == false then return nil, remove_err or "could not remove temporary output file" end
	return true
end

return M
