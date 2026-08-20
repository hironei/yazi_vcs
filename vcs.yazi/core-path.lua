-- core-path.lua
-- Pure path utilities. No Yazi API calls, so this file can be `require`d
-- and its functions called under a plain `lua` interpreter for unit tests.
local M = {}

--- Replace backslashes with forward slashes.
---@param p string
---@return string
function M.to_slash(p)
	return (p:gsub("\\", "/"))
end

--- Replace forward slashes with backslashes.
---@param p string
---@return string
function M.to_backslash(p)
	return (p:gsub("/", "\\"))
end

--- Strip one or more trailing slashes (either style), except for a root
--- like "/" or "C:/" where stripping would leave an empty or invalid path.
---@param p string
---@return string
function M.trim_trailing_slash(p)
	if #p <= 1 then
		return p
	end
	local trimmed = p:gsub("[/\\]+$", "")
	if trimmed == "" then
		return p:sub(1, 1)
	end
	-- Keep the slash on a bare Windows drive root ("C:/" -> "C:/").
	if trimmed:match("^%a:$") then
		return trimmed .. "/"
	end
	return trimmed
end

local function comparison_path(p)
	p = M.trim_trailing_slash(M.to_slash(p))
	if p:match("^%a:/") or p:sub(1, 2) == "//" then return p:lower() end
	return p
end

--- Whether `target` is `root` itself or a descendant of it.
--- Windows drive and UNC paths are compared case-insensitively; POSIX paths
--- remain case-sensitive.
---@param root string
---@param target string
---@return boolean
function M.is_within(root, target)
	root = comparison_path(root)
	target = comparison_path(target)
	if target == root then
		return true
	end
	local boundary = root:sub(-1) == "/" and root or (root .. "/")
	return target:sub(1, #boundary) == boundary
end

--- Return `target`'s path relative to `root` (slash-separated, no leading
--- slash). Returns "" if `target == root`. Returns `nil` if `target` is not
--- within `root`.
---@param root string
---@param target string
---@return string?
function M.strip_prefix(root, target)
	if not M.is_within(root, target) then
		return nil
	end
	local comparable_root = comparison_path(root)
	local comparable_target = comparison_path(target)
	root = M.trim_trailing_slash(M.to_slash(root))
	target = M.to_slash(target)
	if comparable_target == comparable_root then
		return ""
	end
	local prefix_length = root:sub(-1) == "/" and #root or (#root + 1)
	return target:sub(prefix_length + 1)
end

--- Return the directory containing `path`.
---@param path string
---@return string
function M.parent(path)
	path = M.trim_trailing_slash(M.to_slash(path))
	local slash = path:match("^.*()/")
	if not slash then return path end
	local parent = path:sub(1, slash - 1)
	if parent == "" then return "/" end
	if parent:match("^%a:$") then return parent .. "/" end
	return parent
end

--- Compare filesystem paths for repository identity.
--- Windows drive and UNC paths are case-insensitive; POSIX paths are not.
---@param left string
---@param right string
---@return boolean
function M.same(left, right)
	left = M.trim_trailing_slash(M.to_slash(left))
	right = M.trim_trailing_slash(M.to_slash(right))
	if left == right then return true end
	local windows = left:match("^%a:/") or right:match("^%a:/")
		or left:sub(1, 2) == "//" or right:sub(1, 2) == "//"
	return windows and left:lower() == right:lower() or false
end

--- Join a root path and a slash-separated relative path, native-separated.
---@param root string
---@param rel string
---@param windows boolean
---@return string
function M.join_native(root, rel, windows)
	root = M.trim_trailing_slash(M.to_slash(root))
	local full = rel == "" and root or (root .. "/" .. rel)
	return windows and M.to_backslash(full) or full
end

return M
