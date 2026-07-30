return function(t)
	local runner = require("core-runner")
	t.deep_eq(runner.split_argv({ "git", "diff", "--", "a b.txt" }), "git", "split_argv command")
	t.deep_eq(runner.command_spec({ command = "git", args = { "status" }, cwd = "/repo" }), { command = "git", args = { "status" }, cwd = "/repo" }, "command spec")
	t.eq(runner.summary("  first\nsecond  ", 240), "first\nsecond", "summary trims output")
	t.eq(runner.summary("abcdef", 3), "abc...", "summary limits long output")
	t.truthy(runner.error_text({ stderr = "failed\n", status = { code = 1 } }, nil):match("failed"), "stderr is preferred")
	t.truthy(runner.error_text(nil, "spawn error"):match("spawn error"), "spawn error is formatted")

	do
		local poll_ms, expired = runner.next_poll(nil, 1000)
		t.eq(expired, false, "disabled timeout (deadline=nil) never expires")
		t.eq(poll_ms, 60000, "disabled timeout polls with a fixed 60s window")
	end
	do
		local poll_ms, expired = runner.next_poll(5000, 1000)
		t.eq(expired, false, "not yet expired while now < deadline")
		t.eq(poll_ms, 4000, "poll window is the exact remaining time")
	end
	do
		local poll_ms, expired = runner.next_poll(1000, 1000)
		t.truthy(expired, "deadline reached exactly at now")
		t.eq(poll_ms, 0, "expired poll window is reported as 0")
	end
	do
		local poll_ms, expired = runner.next_poll(1000, 5000)
		t.truthy(expired, "deadline already passed")
		t.eq(poll_ms, 0, "already-passed poll window is reported as 0")
	end
end
