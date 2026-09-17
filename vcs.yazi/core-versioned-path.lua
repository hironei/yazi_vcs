-- core-versioned-path.lua
-- Determine whether a path itself is versioned when aggregated status may
-- have classified it as untracked because of a changed child.
local Runner = require(".core-runner")
local SvnBackend = require(".backend-svn")

local M = {}

---@param kind "git"|"svn"
---@param root string
---@param pathname string root-relative path
---@param cfg table
---@return boolean|nil versioned
---@return any? err
function M.query(kind, root, pathname, cfg)
	local args
	if kind == "git" then
		args = { "--literal-pathspecs", "ls-files", "--cached", "--", pathname }
	elseif kind == "svn" then
		args = SvnBackend.versioned_path_args(pathname)
	else
		return nil, "unsupported VCS kind: " .. tostring(kind)
	end

	local output, err = Runner.run({ command = kind, args = args, cwd = root }, cfg.runner.timeout_ms, cfg.runner.audit)
	if not output then return nil, err or (kind .. " path query failed") end
	if output.timed_out then return nil, Runner.error_text(output, err) end
	if not output.status.success then
		-- An SVN info failure is the normal result for an unversioned path.
		-- Git ls-files reports the same case through successful empty output.
		if kind == "svn" then return false end
		return nil, Runner.error_text(output, err)
	end

	if kind == "git" then return tostring(output.stdout or ""):match("%S") ~= nil end
	local item = Runner.summary(output.stdout, 40)
	-- `svn info --show-item kind` returns `dir` or `file`.
	return item == "dir" or item == "file"
end

return M
