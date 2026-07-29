-- core-detector.lua
-- VCS kind + root detection (requirements §6).
--
-- `find_git_root` / `find_svn_root` / `pick` are expressed against an
-- injected `fsops` table (or plain strings, for `pick`) so they can be
-- unit-tested under a plain `lua` interpreter without Yazi's `fs`/`Url`
-- globals. `M.detect` is the Yazi-facing adapter that operates on real
-- `Url` objects and is exercised only inside Yazi itself.
local M = {}

--- Find the Git repository root by walking `dir` upward looking for
--- `.git`. `.git` may be a directory (normal repo) or a file starting
--- with "gitdir: " (worktree / submodule) — requirements §6.2. Uses no
--- subprocess, mirroring the official `git.yazi` plugin.
---@param dir any             opaque directory handle
---@param fsops table         { join(dir,name)->handle, parent(dir)->handle|nil, cha(handle)->{is_dir:boolean}|nil, read_head(handle,n)->string|nil }
---@return any?               the repository root handle, or nil
function M.find_git_root(dir, fsops)
	while dir do
		local git = fsops.join(dir, ".git")
		local cha = fsops.cha(git)
		if cha then
			if cha.is_dir then
				return dir
			end
			if fsops.read_head(git, 8) == "gitdir: " then
				return dir
			end
		end
		dir = fsops.parent(dir)
	end
	return nil
end

--- Find the SVN working-copy root by walking `dir` upward looking for a
--- `.svn` directory. SVN >= 1.7 stores metadata only at the working-copy
--- root, so the first `.svn` found while walking up is that root
--- (verified empirically against SVN 1.14: `svn info --show-item
--- wc-root` from a subdirectory resolves to the same directory that
--- holds the sole `.svn`) — requirements §6.3.
---@param dir any
---@param fsops table
---@return any?
function M.find_svn_root(dir, fsops)
	while dir do
		local svn = fsops.join(dir, ".svn")
		local cha = fsops.cha(svn)
		if cha and cha.is_dir then
			return dir
		end
		dir = fsops.parent(dir)
	end
	return nil
end

--- Choose between a detected Git root and SVN root per requirements §6.4:
--- the root closer to the starting directory wins; if both resolve to
--- the exact same directory, `priority` decides.
---@param git_root any?    anything `tostring`-able; longer string = deeper path
---@param svn_root any?
---@param priority string[]  e.g. { "git", "svn" }
---@return "git"|"svn"|nil kind
---@return any? root
function M.pick(git_root, svn_root, priority)
	if git_root and svn_root then
		local g, s = tostring(git_root), tostring(svn_root)
		if g == s then
			local kind = priority[1]
			return kind, (kind == "git" and git_root or svn_root)
		elseif #g > #s then
			return "git", git_root
		else
			return "svn", svn_root
		end
	elseif git_root then
		return "git", git_root
	elseif svn_root then
		return "svn", svn_root
	end
	return nil, nil
end

--- Build an `fsops` implementation backed by real Yazi APIs.
--- Never called at module load time, so this file remains loadable (and
--- its pure functions above callable) under a plain `lua` interpreter.
---@return table
local function real_fsops()
	return {
		join = function(dir, name)
			return dir:join(name)
		end,
		parent = function(dir)
			return dir.parent
		end,
		cha = function(handle)
			return fs.cha(handle)
		end,
		read_head = function(handle, n)
			local file = io.open(tostring(handle))
			if not file then
				return nil
			end
			local head = file:read(n)
			file:close()
			return head
		end,
	}
end

--- Detect the VCS kind and root for `cwd`.
---@param cwd Url
---@param priority string[]
---@return "git"|"svn"|nil kind
---@return Url? root
function M.detect(cwd, priority)
	local fsops = real_fsops()
	local git_root = M.find_git_root(cwd, fsops)
	local svn_root = M.find_svn_root(cwd, fsops)
	return M.pick(git_root, svn_root, priority)
end

return M
