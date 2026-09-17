return function(t)
	local runner = require("core-runner")
	t.deep_eq(runner.split_argv({ "git", "diff", "--", "a b.txt" }), "git", "split_argv command")
	t.deep_eq(runner.command_spec({ command = "git", args = { "status" }, cwd = "/repo" }), { command = "git", args = { "status" }, cwd = "/repo" }, "command spec")
	t.eq(runner.summary("  first\nsecond  ", 240), "first\nsecond", "summary trims output")
	t.eq(runner.summary("abcdef", 3), "abc...", "summary limits long output")
	t.truthy(runner.error_text({ stderr = "failed\n", status = { code = 1 } }, nil):match("failed"), "stderr is preferred")
	t.truthy(runner.error_text(nil, "spawn error"):match("spawn error"), "spawn error is formatted")
	t.eq(
		runner.mask_text("password=secret token:abc https://alice:pw@example.com Authorization: Bearer XYZ"),
		"password=[REDACTED] token:[REDACTED] https://[REDACTED]@example.com Authorization: [REDACTED]",
		"mask_text removes credential-like values"
	)
	t.deep_eq(
		runner.mask_args({ "--token", "secret", "--password=also-secret", "https://alice:pw@example.com" }),
		{ "--token", "[REDACTED]", "--password=[REDACTED]", "https://[REDACTED]@example.com" },
		"mask_args removes standalone and embedded credential values"
	)
	t.eq(
		runner.mask_text("Authorization: Basic basic-secret"),
		"Authorization: [REDACTED]",
		"mask_text removes Basic authorization values"
	)
	t.eq(
		runner.mask_text("git -c http.extraHeader=Authorization: Token token-secret"),
		"git -c http.extraHeader=Authorization: [REDACTED]",
		"mask_text removes arbitrary authorization schemes in http.extraHeader arguments"
	)
	t.deep_eq(
		runner.mask_args({ "-c", "http.extraHeader=Authorization: Negotiate negotiate-secret" }),
		{ "-c", "http.extraHeader=Authorization: [REDACTED]" },
		"mask_args removes arbitrary authorization schemes in a Git config argument"
	)
	t.eq(runner.mask_text("basic usage: use --help"), "basic usage: use --help", "mask_text leaves ordinary Basic text unchanged")
	t.eq(
		runner.mask_text("GITHUB_TOKEN=github-secret private_token:private-secret oauth_token=oauth-secret"),
		"GITHUB_TOKEN=[REDACTED] private_token:[REDACTED] oauth_token=[REDACTED]",
		"mask_text matches credential key names containing token"
	)
	t.eq(
		runner.mask_text("https://u:p@ss@host.example/repo"),
		"https://[REDACTED]@host.example/repo",
		"mask_text masks URL userinfo through the last at-sign"
	)

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
		local calls = { events = events, killed = 0, waited = 0, dropped = 0, debug_messages = {} }
		local child = {}
		function child:read_line_with(_)
			local event = table.remove(calls.events, 1)
			if type(event) == "table" then return event.line, event.stream end
			return nil, event
		end
		function child:start_kill() calls.killed = calls.killed + 1 end
		function child:wait()
			calls.waited = calls.waited + 1
			if calls.wait_error then return nil, calls.wait_error end
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
				function command:spawn()
					if calls.spawn_error then return nil, calls.spawn_error end
					return child
				end
				function command:status()
					if calls.status_error then error(calls.status_error) end
					return status, calls.status_return_error
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
		_G.ya = {
			time = function() return 0 end,
			dbg = function(message) calls.debug_messages[#calls.debug_messages + 1] = message end,
		}
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
			t.eq(#calls.debug_messages, 0, "audit logging is disabled by default")
		end)
	end

	do
		local Command, calls = fake_command({ { line = "safe output", stream = 0 }, { line = "password=secret", stream = 1 }, 2 }, { success = false, code = 7 })
		with_fake_yazi(Command, calls, function()
			local output, err = runner.run({ command = "git", args = { "push", "--token", "secret" }, cwd = "https://alice:pw@example.com/repo" }, 1000, { enabled = true })
			t.falsy(err, "audited runner still returns command result")
			t.eq(output.status.code, 7, "audited runner preserves exit code")
			t.eq(#calls.debug_messages, 1, "enabled audit logging records one run")
			t.truthy(calls.debug_messages[1]:match('"command":"git"'), "audit includes command")
			t.truthy(calls.debug_messages[1]:match('"exit_code":7'), "audit includes exit code")
			t.truthy(calls.debug_messages[1]:match("%[REDACTED%]"), "audit masks credential-like values")
			t.falsy(calls.debug_messages[1]:match("secret"), "audit does not contain the token or stderr secret")
		end)
	end

	do
		local Command, calls = fake_command({
			{ line = "out-1\n", stream = 0 },
			{ line = "out-2\n", stream = 0 },
			{ line = "err-1\n", stream = 1 },
			2,
		}, { success = true, code = 0 })
		with_fake_yazi(Command, calls, function()
			local output = runner.run({ command = "git", args = { "status" } }, 1000)
			t.eq(output.stdout, "out-1\nout-2\n", "runner does not double Yazi line terminators")
			t.eq(output.stderr, "err-1\n", "runner preserves stderr terminators")
		end)
	end

	do
		local Command, calls = fake_command({ { line = "timeout stderr", stream = 1 }, 3 }, { success = false, code = 137 })
		with_fake_yazi(Command, calls, function()
			local output, err = runner.run({ command = "git", args = { "status" } }, 10, { enabled = true })
			t.falsy(err, "timeout is returned as a command result")
			t.truthy(output.timed_out, "runner marks a timed-out child")
			t.eq(output.status.success, false, "timed-out child is unsuccessful")
			t.eq(calls.killed, 1, "runner kills a timed-out child")
			t.eq(calls.waited, 1, "runner waits after killing a timed-out child")
			t.eq(#calls.debug_messages, 1, "audit records a timeout")
			t.eq(output.stderr, "timeout stderr", "timeout preserves captured stderr")
			t.truthy(calls.debug_messages[1]:match('"error":"command timed out"'), "timeout reason is recorded as error")
		end)
	end

	do
		local Command, calls = fake_command({}, { success = true, code = 0 })
		calls.spawn_error = "spawn failed"
		with_fake_yazi(Command, calls, function()
			local output, err = runner.run({ command = "git", args = { "status" } }, 1000, { enabled = true })
			t.falsy(output, "runner returns no output after a spawn failure")
			t.eq(err, "spawn failed", "runner returns the spawn failure")
			t.eq(#calls.debug_messages, 1, "audit records a spawn failure")
			t.truthy(calls.debug_messages[1]:match('"exit_code":null'), "spawn failure has no exit code")
			t.truthy(calls.debug_messages[1]:match('"error":"spawn failed"'), "spawn failure reason is recorded separately")
			t.truthy(calls.debug_messages[1]:match('"stderr":null'), "spawn failure has no captured stderr")
		end)
	end

	do
		local Command, calls = fake_command({}, { success = true, code = 0 })
		with_fake_yazi(Command, calls, function()
			local status, err = runner.interactive({ command = "git", args = { "pull" } }, { enabled = true })
			t.falsy(err, "interactive command has no error on success")
			t.truthy(status.success, "interactive command returns its status")
			t.eq(calls.stdin, Command.INHERIT, "interactive runner inherits stdin")
			t.eq(calls.stdout, Command.INHERIT, "interactive runner inherits stdout")
			t.eq(calls.stderr, Command.INHERIT, "interactive runner inherits stderr")
			t.eq(calls.dropped, 1, "interactive runner drops the permit on success")
			t.eq(#calls.debug_messages, 1, "enabled audit logging records one interactive call")
			t.truthy(calls.debug_messages[1]:match('"stderr":null'), "interactive audit does not capture terminal stderr")
		end)
	end

	do
		local Command, calls = fake_command({}, { success = true, code = 0 })
		calls.construct_error = "construction failed"
		with_fake_yazi(Command, calls, function()
			local status, err = runner.interactive({ command = "missing" }, { enabled = true })
			t.falsy(status, "interactive runner returns no status after a Lua error")
			t.truthy(tostring(err):match("construction failed"), "interactive runner returns the Lua error")
			t.eq(calls.dropped, 1, "interactive runner drops the permit after a Lua error")
			t.eq(#calls.debug_messages, 1, "audit records an interactive Lua error")
			t.truthy(calls.debug_messages[1]:match('"stderr":null'), "interactive Lua errors do not become stderr")
			t.truthy(calls.debug_messages[1]:match('"error":".-construction failed"'), "interactive Lua error is recorded separately")
		end)
	end

	do
		local Command, calls = fake_command({}, { success = true, code = 0 })
		calls.status_error = "status failed"
		with_fake_yazi(Command, calls, function()
			local status, err = runner.interactive({ command = "missing" }, { enabled = true })
			t.falsy(status, "interactive runner returns no status after status failure")
			t.truthy(tostring(err):match("status failed"), "status failure is returned to the caller")
			t.eq(#calls.debug_messages, 1, "audit records an interactive status failure")
			t.truthy(calls.debug_messages[1]:match('"exit_code":null'), "status failure has no exit code")
			t.truthy(calls.debug_messages[1]:match('"error":".-status failed"'), "status failure reason is recorded separately")
		end)
	end
end
