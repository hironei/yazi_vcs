-- tests/test-core-vcs-info.lua
return function(t)
	local info = require("core-vcs-info")
	local git = require("backend-git")
	local svn_backend = require("backend-svn")

	t.deep_eq(git.info_spec("C:/repo"), {
		command = "git",
		args = { "branch", "--show-current" },
		cwd = "C:/repo",
	}, "Git metadata uses the repository root as cwd")
	t.deep_eq(svn_backend.info_spec("C:/wc"), {
		command = "svn",
		args = { "info", "--show-item", "url" },
		cwd = "C:/wc",
	}, "SVN metadata requests the working-copy URL")
	t.deep_eq(svn_backend.revision_spec("C:/wc", "sub/file.txt"), {
		command = "svn",
		args = { "info", "--show-item", "revision", "--", "sub/file.txt" },
		cwd = "C:/wc",
	}, "SVN revision metadata is queried for one root-relative target")
	t.deep_eq(git.revision_spec("C:/repo"), {
		command = "git",
		args = { "rev-parse", "--short", "HEAD" },
		cwd = "C:/repo",
	}, "Git revision metadata requests the short HEAD hash")

	t.deep_eq(info.parse_git("codex/fix-vcs-task-hang\n"), { branch = "codex/fix-vcs-task-hang" }, "Git branch output is trimmed")
	t.deep_eq(info.parse_git("\n"), { branch = "HEAD (detached)" }, "detached Git HEAD has a visible fallback")

	local svn = info.parse_svn("https://host/svn/base_url/trunk\n")
	t.eq(info.svn_target_url(svn.url, ""), "https://host/svn/base_url/trunk", "SVN root target keeps the cached working-copy URL")
	t.eq(info.svn_target_url(svn.url, "sub/file.txt"), "https://host/svn/base_url/trunk/sub/file.txt", "SVN target URL appends the root-relative path")
	t.eq(info.svn_target_url(svn.url, "."), "https://host/svn/base_url/trunk", "SVN root target accepts the relative dot")
	t.eq(info.decode_percent_utf8("%E6%97%A5%E6%9C%AC%E8%AA%9E"), "日本語", "percent-encoded UTF-8 decodes to readable Unicode")
	t.eq(
		info.svn_target_url("https://host/svn/%E6%97%A5%E6%9C%AC", "docs/%E8%B3%87%E6%96%99.txt"),
		"https://host/svn/日本/docs/資料.txt",
		"SVN target URLs decode encoded Unicode in root and relative paths"
	)
	t.eq(
		info.format("svn", { url = "https://host/svn/%E6%97%A5%E6%9C%AC" }, "資料.txt"),
		"(svn: https://host/svn/日本/資料.txt)",
		"status-bar SVN formatting uses the same readable target URL"
	)
	t.eq(
		info.svn_target_url("https://host/svn/%E6%97%A5%E6%9C%AC", "資料.txt") .. "@42",
		"https://host/svn/日本/資料.txt@42",
		"revision suffix remains intact after URL decoding"
	)
	t.eq(
		info.svn_target_url("https://host/svn/trunk", "日本語/a+b%20file%2Fname.txt"),
		"https://host/svn/trunk/日本語/a+b%20file%2Fname.txt",
		"SVN URL presentation preserves literal plus, spaces, and encoded delimiters"
	)
	t.eq(
		info.decode_percent_utf8("bad-%E6%97-incomplete-%ZZ-%E6%28%A1"),
		"bad-%E6%97-incomplete-%ZZ-%E6%28%A1",
		"malformed percent escapes remain unchanged"
	)
	t.eq(info.decode_percent_utf8("%41%20ASCII"), "%41%20ASCII", "ASCII percent escapes remain unchanged")
	t.eq(info.format("svn", svn, "sub/file.txt"), "(svn: https://host/svn/base_url/trunk/sub/file.txt)", "SVN metadata is formatted for the active target")
	t.eq(info.git_target("main", "."), "main", "Git root target omits the path")
	t.eq(info.git_target("main", "src/foo.lua"), "main/src/foo.lua", "Git target appends the root-relative path")
	t.eq(info.git_target("main", "%E6%97%A5%E6%9C%AC.txt"), "main/%E6%97%A5%E6%9C%AC.txt", "Git copy identifiers remain unchanged")
	t.eq(info.format("git", { branch = "main" }), "(main)", "Git metadata is formatted like a shell prompt")
	t.falsy(info.format("git", nil), "missing metadata is not rendered")
	t.truthy(info.refresh_due(nil, 1000, 5000), "metadata is fetched when no refresh timestamp exists")
	t.falsy(info.refresh_due(1000, 5999, 5000), "metadata remains cached before the refresh interval")
	t.truthy(info.refresh_due(1000, 6000, 5000), "metadata refreshes at the configured interval")
	t.truthy(info.refresh_due(1000, 1001, 0), "zero interval forces metadata refresh")
end
