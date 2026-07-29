return function(t)
	local external = require("core-external")
	t.eq(external.environment({ WSL_INTEROP = "/run/interop" }, "linux"), "wsl", "WSL environment detected")
	t.eq(external.environment({ MSYSTEM = "MINGW64" }, "windows"), "git-bash", "Git Bash environment detected")
	t.eq(external.environment({}, "windows"), "windows", "native Windows environment detected")
	t.eq(external.path_style("auto", "wsl"), "windows", "auto WSL path style")
	t.eq(external.path_style("native", "wsl"), "native", "native path style override")
	t.eq(external.converter("wsl"), "wslpath", "WSL converter")
	t.eq(external.converter("git-bash"), "cygpath", "Git Bash converter")
	local args = external.expand_args({ "--root={root}", "--file={file}", "{targets}", "rev={revision}" }, {
		root = "/repo", file = "/repo/a.txt", targets = { "/repo/a.txt", "/repo/b b.txt" }, revision = "HEAD",
	})
	t.deep_eq(args, { "--root=/repo", "--file=/repo/a.txt", "/repo/a.txt", "/repo/b b.txt", "rev=HEAD" }, "external placeholders expand safely")
	local invalid, reason = external.expand_args({ "--path={targets}" }, { targets = { "a", "b" } })
	t.falsy(invalid, "embedded targets placeholder is rejected")
	t.truthy(reason, "invalid placeholder returns a reason")
	t.truthy(external.validate({ command = "lazygit", args = {} }), "external command validates")
	t.falsy(external.validate({ command = "" }), "empty external command is rejected")
end
