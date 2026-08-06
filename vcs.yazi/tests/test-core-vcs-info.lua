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
	t.deep_eq(svn_backend.repository_root_info_spec("C:/wc"), {
		command = "svn",
		args = { "info", "--show-item", "repos-root-url" },
		cwd = "C:/wc",
	}, "SVN metadata requests the repository root URL")
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

	local svn = info.parse_svn("https://host/svn/base_url/trunk\n", "https://host/svn/base_url\n")
	t.eq(info.svn_target_url(svn.url, ""), "https://host/svn/base_url/trunk", "SVN root target keeps the cached working-copy URL")
	t.eq(info.svn_target_url(svn.url, "sub/file.txt"), "https://host/svn/base_url/trunk/sub/file.txt", "SVN target URL appends the root-relative path")
	t.eq(info.svn_target_url(svn.url, "."), "https://host/svn/base_url/trunk", "SVN root target accepts the relative dot")
	t.eq(info.format("svn", svn, "sub/file.txt"), "(svn: https://host/svn/base_url/trunk/sub/file.txt)", "SVN metadata is formatted for the active target")
	t.eq(info.git_target("main", "."), "main", "Git root target omits the path")
	t.eq(info.git_target("main", "src/foo.lua"), "main/src/foo.lua", "Git target appends the root-relative path")
	t.eq(
		info.svn_location("https://host/svn/base_url/branches/topic", "https://host/svn/base_url"),
		"base_url/branches/topic",
		"legacy SVN location helper remains pure"
	)
	t.eq(info.format("git", { branch = "main" }), "(main)", "Git metadata is formatted like a shell prompt")
	t.falsy(info.format("git", nil), "missing metadata is not rendered")
end
