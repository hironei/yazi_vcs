-- tests/test-core-detector.lua
--
-- `find_git_root`/`find_svn_root` are exercised against a fake in-memory
-- filesystem (a table of directory -> children), not the real `fs`/`Url`
-- Yazi globals, which don't exist under a plain `lua` interpreter.
return function(t)
	local detector = require("core-detector")

	--- Build an `fsops` implementation over `fs`, a table describing a
	--- tree with plain "/"-joined string paths as directory handles.
	---@param fs table<string, table>  path -> { [".git"]="dir"|"file:<content>", [".svn"]="dir", parent="..." }
	local function fake_fsops(fs)
		return {
			join = function(dir, name)
				return dir == "/" and ("/" .. name) or (dir .. "/" .. name)
			end,
			parent = function(dir)
				local node = fs[dir]
				return node and node.parent or nil
			end,
			cha = function(handle)
				local kind = fs[handle] and fs[handle].kind
				if not kind then
					return nil
				end
				return { is_dir = kind == "dir" }
			end,
			read_head = function(handle, n)
				local node = fs[handle]
				if not node or node.kind ~= "file" then
					return nil
				end
				return node.content:sub(1, n)
			end,
		}
	end

	-- Plain repo: `.git` is a directory at /repo.
	do
		local fs = {
			["/repo"] = { parent = "/" },
			["/repo/.git"] = { kind = "dir" },
			["/repo/src"] = { parent = "/repo" },
			["/"] = { parent = nil },
		}
		local root = detector.find_git_root("/repo/src", fake_fsops(fs))
		t.eq(root, "/repo", "find_git_root walks up to a directory .git")
	end

	-- Worktree/submodule: `.git` is a *file* starting with "gitdir: ".
	do
		local fs = {
			["/repo"] = { parent = "/" },
			["/repo/.git"] = { kind = "file", content = "gitdir: /main/.git/worktrees/repo\n" },
			["/"] = { parent = nil },
		}
		local root = detector.find_git_root("/repo", fake_fsops(fs))
		t.eq(root, "/repo", "find_git_root recognizes a worktree .git file")
	end

	-- A `.git` file that is NOT a gitdir pointer (e.g. some unrelated
	-- file) must not be mistaken for a repo root.
	do
		local fs = {
			["/repo"] = { parent = "/" },
			["/repo/.git"] = { kind = "file", content = "not a gitdir pointer" },
			["/"] = { parent = nil },
		}
		local root = detector.find_git_root("/repo", fake_fsops(fs))
		t.eq(root, nil, "find_git_root rejects a .git file without the gitdir: prefix")
	end

	-- No .git anywhere up to the walked root.
	do
		local fs = {
			["/a/b/c"] = { parent = "/a/b" },
			["/a/b"] = { parent = "/a" },
			["/a"] = { parent = "/" },
			["/"] = { parent = nil },
		}
		local root = detector.find_git_root("/a/b/c", fake_fsops(fs))
		t.eq(root, nil, "find_git_root returns nil when no .git is found")
	end

	-- Some Windows URL backends represent a filesystem root by returning the
	-- root itself from `parent`. Detection must terminate rather than leave a
	-- fetcher/action task running indefinitely.
	do
		local fs = {
			["C:/repo"] = { parent = "C:/" },
			["C:/"] = { parent = "C:/" },
		}
		local root = detector.find_git_root("C:/repo", fake_fsops(fs))
		t.eq(root, nil, "find_git_root terminates when parent returns itself")
	end

	-- SVN: single .svn at the working-copy root, found from a subdirectory.
	do
		local fs = {
			["/wc"] = { parent = "/" },
			["/wc/.svn"] = { kind = "dir" },
			["/wc/sub"] = { parent = "/wc" },
			["/"] = { parent = nil },
		}
		local root = detector.find_svn_root("/wc/sub", fake_fsops(fs))
		t.eq(root, "/wc", "find_svn_root walks up to the sole .svn directory")
	end

	-- A non-trivial parent cycle must also terminate when no SVN root exists.
	do
		local fs = {
			["/a"] = { parent = "/b" },
			["/b"] = { parent = "/a" },
		}
		local root = detector.find_svn_root("/a", fake_fsops(fs))
		t.eq(root, nil, "find_svn_root terminates on a parent cycle")
	end

	-- pick(): closer root wins regardless of priority order.
	t.deep_eq({ detector.pick("/a/b/c", "/a", { "svn", "git" }) }, { "git", "/a/b/c" }, "pick prefers the deeper (closer) root")
	t.deep_eq({ detector.pick("/a", "/a/b/c", { "git", "svn" }) }, { "svn", "/a/b/c" }, "pick prefers the deeper root regardless of which VCS")

	-- pick(): same directory -> priority decides.
	t.deep_eq({ detector.pick("/a", "/a", { "git", "svn" }) }, { "git", "/a" }, "pick uses priority[1] when both roots are the same dir")
	t.deep_eq({ detector.pick("/a", "/a", { "svn", "git" }) }, { "svn", "/a" }, "pick honors a reversed priority list")

	-- pick(): only one found.
	t.deep_eq({ detector.pick("/a", nil, { "git", "svn" }) }, { "git", "/a" }, "pick returns the git root when svn wasn't found")
	t.deep_eq({ detector.pick(nil, "/a", { "git", "svn" }) }, { "svn", "/a" }, "pick returns the svn root when git wasn't found")
	t.deep_eq({ detector.pick(nil, nil, { "git", "svn" }) }, { nil, nil }, "pick returns nil, nil when neither was found")
end
