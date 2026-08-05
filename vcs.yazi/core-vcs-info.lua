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

function M.parse_svn(url, repository_root)
	return { url = trim(url), repository_root = trim(repository_root) }
end

function M.svn_location(url, repository_root)
	url = trim_slashes(url)
	repository_root = trim_slashes(repository_root)
	if repository_root ~= "" and (url == repository_root or url:sub(1, #repository_root + 1) == repository_root .. "/") then
		local relative = url:sub(#repository_root + 1):gsub("^/+", "")
		local name = repository_root:match("([^/]+)$") or repository_root
		return relative == "" and name or name .. "/" .. relative
	end
	return url
end

function M.format(kind, info)
	if not info then return nil end
	if kind == "git" and info.branch and info.branch ~= "" then
		return "(" .. info.branch .. ")"
	end
	if kind == "svn" and info.url and info.url ~= "" then
		return "(svn: " .. M.svn_location(info.url, info.repository_root) .. ")"
	end
	return nil
end

return M
