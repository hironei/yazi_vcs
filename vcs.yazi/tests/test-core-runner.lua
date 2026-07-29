return function(t)
	local runner = require("core-runner")
	t.deep_eq(runner.split_argv({ "git", "diff", "--", "a b.txt" }), "git", "split_argv command")
	t.deep_eq(runner.command_spec({ command = "git", args = { "status" }, cwd = "/repo" }), { command = "git", args = { "status" }, cwd = "/repo" }, "command spec")
	t.eq(runner.summary("  first\nsecond  ", 240), "first\nsecond", "summary trims output")
	t.eq(runner.summary("abcdef", 3), "abc...", "summary limits long output")
	t.truthy(runner.error_text({ stderr = "failed\n", status = { code = 1 } }, nil):match("failed"), "stderr is preferred")
	t.truthy(runner.error_text(nil, "spawn error"):match("spawn error"), "spawn error is formatted")
end
