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

	t.deep_eq(info.parse_git("codex/fix-vcs-task-hang\n"), { branch = "codex/fix-vcs-task-hang" }, "Git branch output is trimmed")
	t.deep_eq(info.parse_git("\n"), { branch = "HEAD (detached)" }, "detached Git HEAD has a visible fallback")

	local svn = info.parse_svn("https://host/svn/base_url/trunk\n", "https://host/svn/base_url\n")
	t.eq(info.svn_location(svn.url, svn.repository_root), "base_url/trunk", "SVN trunk is shown relative to the repository root")
	t.eq(info.format("svn", svn), "(svn: base_url/trunk)", "SVN metadata is formatted for the status bar")
	t.eq(
		info.svn_location("https://host/svn/base_url/branches/topic", "https://host/svn/base_url"),
		"base_url/branches/topic",
		"SVN branch paths remain visible"
	)
	t.eq(info.format("git", { branch = "main" }), "(main)", "Git metadata is formatted like a shell prompt")
	t.falsy(info.format("git", nil), "missing metadata is not rendered")
end
