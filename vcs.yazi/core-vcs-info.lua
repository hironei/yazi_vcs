-- core-vcs-info.lua
-- Pure parsing and formatting for repository metadata shown in the status bar.
local M = {}

local function trim(value)
	return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function trim_slashes(value)
	return (trim(value):gsub("/+$", ""))
end

function M.parse_git(stdout)
	local branch = trim(stdout)
	return { branch = branch ~= "" and branch or "HEAD (detached)" }
end

function M.parse_svn(url)
	return { url = trim(url) }
end

local function relative_path(relpath)
	relpath = tostring(relpath or ""):gsub("\\\\", "/"):gsub("^/+", "")
	return relpath == "." and "" or relpath
end

--- Build the URL for a path below an already-known SVN working-copy URL.
--- This is intentionally pure: the caller supplies the root URL and the
--- root-relative path computed from the local filesystem path.
---@param root_url string
---@param relpath string|nil  slash-separated, root-relative path; '.' is the root
---@return string
function M.svn_target_url(root_url, relpath)
	root_url = trim_slashes(root_url)
	relpath = relative_path(relpath)
	if root_url == "" then return relpath end
	return relpath == "" and root_url or root_url .. "/" .. relpath
end

--- Build the branch/path identifier used by the Git clipboard actions.
---@param branch string
---@param relpath string|nil  slash-separated, root-relative path; '.' is the root
---@return string
function M.git_target(branch, relpath)
	branch = trim(branch)
	relpath = relative_path(relpath)
	return relpath == "" and branch or branch .. "/" .. relpath
end

function M.format(kind, info, relpath)
	if not info then return nil end
	if kind == "git" and info.branch and info.branch ~= "" then
		return "(" .. info.branch .. ")"
	end
	if kind == "svn" and info.url and info.url ~= "" then
		return "(svn: " .. M.svn_target_url(info.url, relpath) .. ")"
	end
	return nil
end

return M
