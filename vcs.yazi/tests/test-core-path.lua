-- tests/test-core-path.lua
return function(t)
	local path = require("core-path")

	t.eq(path.to_slash("a\\b\\c"), "a/b/c", "to_slash converts backslashes")
	t.eq(path.to_slash("a/b/c"), "a/b/c", "to_slash is a no-op on forward slashes")
	t.eq(path.to_backslash("a/b/c"), "a\\b\\c", "to_backslash converts forward slashes")

	t.eq(path.trim_trailing_slash("a/b/"), "a/b", "trim_trailing_slash strips one slash")
	t.eq(path.trim_trailing_slash("a/b///"), "a/b", "trim_trailing_slash strips repeated slashes")
	t.eq(path.trim_trailing_slash("/"), "/", "trim_trailing_slash keeps a bare root")
	t.eq(path.trim_trailing_slash("C:/"), "C:/", "trim_trailing_slash keeps a drive root")
	t.eq(path.trim_trailing_slash("C:\\"), "C:/", "trim_trailing_slash keeps a drive root (backslash input)")

	t.truthy(path.is_within("C:/repo", "C:/repo"), "root is within itself")
	t.truthy(path.is_within("C:/", "C:/Users/foo.txt"), "descendant is within a bare drive root")
	t.truthy(path.is_within("/", "/tmp/file.txt"), "descendant is within a POSIX root")
	t.truthy(path.is_within("C:/repo", "C:/repo/sub/file.txt"), "descendant is within root")
	t.truthy(path.is_within("C:\\repo", "C:/repo/sub/file.txt"), "mixed separators still match")
	t.truthy(path.is_within("C:/Repo", "c:/repo/Sub/file.txt"), "Windows path containment ignores case")
	t.falsy(path.is_within("C:/repo", "C:/repository/file.txt"), "a sibling with a shared prefix is not within root")
	t.falsy(path.is_within("C:/repo", "C:/other/file.txt"), "unrelated path is not within root")

	t.eq(path.strip_prefix("C:/repo", "C:/repo"), "", "strip_prefix of the root itself is empty")
	t.eq(path.strip_prefix("C:/repo", "C:/repo/sub/file.txt"), "sub/file.txt", "strip_prefix returns forward-slash relpath")
	t.eq(path.strip_prefix("C:\\repo", "C:\\repo\\sub\\file.txt"), "sub/file.txt", "strip_prefix normalizes backslash input")
	t.eq(path.strip_prefix("C:/Repo", "c:/repo/Sub/file.txt"), "Sub/file.txt", "strip_prefix preserves target case on Windows")
	t.eq(path.strip_prefix("C:/repo", "C:/other/file.txt"), nil, "strip_prefix returns nil outside root")
	t.eq(path.strip_prefix("C:/", "C:/Users/foo.txt"), "Users/foo.txt", "strip_prefix handles a bare drive root")
	t.eq(path.strip_prefix("/", "/tmp/file.txt"), "tmp/file.txt", "strip_prefix handles a POSIX root")

	t.eq(path.join_native("C:/repo", "sub/file.txt", true), "C:\\repo\\sub\\file.txt", "join_native windows")
	t.eq(path.join_native("/repo", "sub/file.txt", false), "/repo/sub/file.txt", "join_native posix")
	t.eq(path.join_native("C:/repo", "", true), "C:\\repo", "join_native with empty relpath returns the root")
end
