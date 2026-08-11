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

	local function fake_command(events, status)
		local calls = { events = events, killed = 0, waited = 0, dropped = 0 }
		local child = {}
		function child:read_line_with(_)
			local event = table.remove(calls.events, 1)
			if type(event) == "table" then return event.line, event.stream end
			return nil, event
		end
		function child:start_kill() calls.killed = calls.killed + 1 end
		function child:wait()
			calls.waited = calls.waited + 1
			return status
		end

		local Command = { NULL = "null", PIPED = "piped", INHERIT = "inherit" }
		setmetatable(Command, {
			__call = function(_, name)
				calls.command = name
				if calls.construct_error then error(calls.construct_error) end
				local command = {}
				function command:arg(args) calls.args = args; return self end
				function command:stdin(value) calls.stdin = value; return self end
				function command:stdout(value) calls.stdout = value; return self end
				function command:stderr(value) calls.stderr = value; return self end
				function command:cwd(value) calls.cwd = value; return self end
				function command:spawn() return child end
				function command:status()
					if calls.status_error then error(calls.status_error) end
					return status
				end
				return command
			end,
		})
		return Command, calls
	end

	local function with_fake_yazi(Command, calls, fn)
		local old_command, old_ui, old_ya = _G.Command, _G.ui, _G.ya
		_G.Command = Command
		_G.ui = { hide = function()
			return { drop = function() calls.dropped = calls.dropped + 1 end }
		end }
		_G.ya = { time = function() return 0 end }
		local ok, err = pcall(fn)
		_G.Command, _G.ui, _G.ya = old_command, old_ui, old_ya
		if not ok then error(err, 0) end
	end

	do
		local Command, calls = fake_command({
			{ line = "out-1", stream = 0 },
			{ line = "err-1", stream = 1 },
			{ line = "out-2", stream = 0 },
			2,
		}, { success = true, code = 0 })
		with_fake_yazi(Command, calls, function()
			local output, err = runner.run({ command = "git", args = { "status" }, cwd = "/repo" }, 1000)
			t.falsy(err, "runner returns no error after successful child wait")
			t.eq(output.stdout, "out-1\nout-2", "runner preserves stdout line order")
			t.eq(output.stderr, "err-1", "runner preserves stderr output")
			t.eq(calls.stdin, Command.NULL, "non-interactive runner closes stdin")
			t.eq(calls.stdout, Command.PIPED, "non-interactive runner pipes stdout")
			t.eq(calls.stderr, Command.PIPED, "non-interactive runner pipes stderr")
			t.eq(calls.waited, 1, "runner waits for the child")
		end)
	end

	do
		local Command, calls = fake_command({ 3 }, { success = false, code = 137 })
		with_fake_yazi(Command, calls, function()
			local output, err = runner.run({ command = "git", args = { "status" } }, 10)
			t.falsy(err, "timeout is returned as a command result")
			t.truthy(output.timed_out, "runner marks a timed-out child")
			t.eq(output.status.success, false, "timed-out child is unsuccessful")
			t.eq(calls.killed, 1, "runner kills a timed-out child")
			t.eq(calls.waited, 1, "runner waits after killing a timed-out child")
		end)
	end

	do
		local Command, calls = fake_command({}, { success = true, code = 0 })
		with_fake_yazi(Command, calls, function()
			local status, err = runner.interactive({ command = "git", args = { "pull" } })
			t.falsy(err, "interactive command has no error on success")
			t.truthy(status.success, "interactive command returns its status")
			t.eq(calls.stdin, Command.INHERIT, "interactive runner inherits stdin")
			t.eq(calls.stdout, Command.INHERIT, "interactive runner inherits stdout")
			t.eq(calls.stderr, Command.INHERIT, "interactive runner inherits stderr")
			t.eq(calls.dropped, 1, "interactive runner drops the permit on success")
		end)
	end

	do
		local Command, calls = fake_command({}, { success = true, code = 0 })
		calls.construct_error = "construction failed"
		with_fake_yazi(Command, calls, function()
			local status, err = runner.interactive({ command = "missing" })
			t.falsy(status, "interactive runner returns no status after a Lua error")
			t.truthy(tostring(err):match("construction failed"), "interactive runner returns the Lua error")
			t.eq(calls.dropped, 1, "interactive runner drops the permit after a Lua error")
		end)
	end
end
