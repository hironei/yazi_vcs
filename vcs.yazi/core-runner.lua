-- core-runner.lua
-- External command execution. Command construction helpers are pure; the
-- execution functions require Yazi and are called only from async actions.
local M = {}

---@param argv string[] command name followed by arguments
---@return string command
---@return string[] args
function M.split_argv(argv)
	return argv[1], { table.unpack(argv, 2) }
end

---@param spec table { command:string, args:string[], cwd:string? }
---@return table
function M.command_spec(spec)
	return {
		command = spec.command,
		args = spec.args or {},
		cwd = spec.cwd,
	}
end

--- Run a command and collect its complete output through Yazi's built-in
--- `Command:output()` path. This is the path used by the official git.yazi
--- fetcher and is suitable for bounded, read-only output such as status,
--- diff, and log.
---@param spec table { command:string, args:string[], cwd:string? }
---@return table|nil output { status={success,code}, stdout:string, stderr:string }
---@return any? err
function M.output(spec)
	local command = Command(spec.command):arg(spec.args or {})
	if spec.cwd then command:cwd(spec.cwd) end
	return command:output()
end

---@param output table|nil
---@param err any
---@return string
function M.error_text(output, err)
	if not output then
		return tostring(err or "unknown error")
	end
	local text = output.stderr or output.stdout or ""
	text = tostring(text):gsub("^%s+", ""):gsub("%s+$", "")
	return text ~= "" and text or ("exit code " .. tostring(output.status and output.status.code or "unknown"))
end

---@param text string|nil
---@param limit integer|nil
---@return string
function M.summary(text, limit)
	text = tostring(text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
	text = text:gsub("^%s+", ""):gsub("%s+$", "")
	limit = limit or 240
	if #text > limit then
		return text:sub(1, limit) .. "..."
	end
	return text
end

local function append_line(lines, line)
	if line then lines[#lines + 1] = line end
end

--- The default `Child:read_line_with` timeout to poll with when
--- `runner.timeout_ms` is disabled (0) — the API has no "block forever"
--- option, so a disabled timeout still needs some finite poll length.
local DISABLED_POLL_MS = 60000

local function now_ms()
	-- `ya.time()` includes milliseconds; `os.time()` is only second-resolution
	-- and makes the runner's deadline unnecessarily coarse in Yazi.
	return math.floor(ya.time() * 1000)
end

--- Decide how long the next `read_line_with` call may block, and whether
--- `deadline` has already been reached. Split out as a pure function so
--- the disabled-timeout (`deadline == nil`) case can be unit-tested
--- without a running Yazi `Command`/`Child`.
---@param deadline integer|nil   ms since epoch the command must finish by, or nil if timeout is disabled
---@param now_ms integer         current time in ms since epoch
---@return integer poll_ms       timeout to pass to `read_line_with`
---@return boolean expired       true if `deadline` has already passed
function M.next_poll(deadline, now_ms)
	if not deadline then
		return DISABLED_POLL_MS, false
	end
	local remaining = deadline - now_ms
	return remaining > 0 and remaining or 0, remaining <= 0
end

--- Run a non-interactive command with piped output. The timeout uses the
--- Child line-read timeout API because Command:output() has no timeout API.
---@param spec table
---@param timeout_ms integer|nil
---@return table|nil output { status={success,code}, stdout, stderr }
---@return any? err
function M.run(spec, timeout_ms)
	local command = Command(spec.command)
		:arg(spec.args or {})
		:stdin(Command.NULL)
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
	if spec.cwd then command:cwd(spec.cwd) end

	local child, spawn_err = command:spawn()
	if not child then return nil, spawn_err end

	local stdout, stderr = {}, {}
	local timeout = tonumber(timeout_ms or 0) or 0
	local deadline = timeout > 0 and (now_ms() + timeout) or nil
	local timed_out = false

	while true do
		local remaining, expired = M.next_poll(deadline, now_ms())
		if expired then
			timed_out = true
			child:start_kill()
			break
		end
		local line, event = child:read_line_with({ timeout = remaining })
		if event == 0 then
			append_line(stdout, line)
		elseif event == 1 then
			append_line(stderr, line)
		elseif event == 3 then
			-- A poll timing out only means the deadline was reached when a
			-- deadline is actually set (requirements §21.1); with
			-- `deadline == nil` (timeout disabled) it just means nothing
			-- was read this poll, so keep waiting.
			if deadline then
				timed_out = true
				child:start_kill()
				break
			end
		elseif event == 2 then
			break
		else
			break
		end
	end

	local status, wait_err = child:wait()
	if not status then return nil, wait_err end
	-- Never write into `status` itself: it's the `Status` userdata `Child:wait()`
	-- returns, which every other call site only ever reads (backend-git.lua,
	-- backend-svn.lua) — on a timeout, substitute a plain table with the same
	-- `success`/`code` shape instead of mutating a value we don't own.
	local result_status = timed_out and { success = false, code = status.code } or status
	-- `read_line_with` line-terminator handling isn't documented; join with
	-- "\n" explicitly rather than assume each returned line still carries
	-- one. A harmless doubled newline if it already did is still parsed
	-- correctly by core-git.lua's `[^\r\n]+`-based line splitters.
	local result = { status = result_status, stdout = table.concat(stdout, "\n"), stderr = table.concat(stderr, "\n") }
	if timed_out then
		result.timed_out = true
		result.stderr = result.stderr ~= "" and result.stderr or "command timed out"
	end
	return result, nil
end

--- Run an editor, pager, or other interactive command while Yazi's terminal is
--- hidden. The permit is always released, including command failures.
---@param spec table
---@return table|nil status
---@return any? err
function M.interactive(spec)
	local permit = ui.hide()
	-- `Command:status()` reports failures as its second return value. Avoid an
	-- xpcall wrapper here: on Windows it can leave Yazi's async task pending
	-- immediately after ui.hide(), before the inherited-terminal command runs.
	local command = Command(spec.command)
		:arg(spec.args or {})
		:stdin(Command.INHERIT)
		:stdout(Command.INHERIT)
		:stderr(Command.INHERIT)
	if spec.cwd then command:cwd(spec.cwd) end
	local status, err = command:status()
	permit:drop()
	return status, err
end

--- Launch a non-interactive GUI process through Yazi's orphan shell action.
--- A direct Command:spawn() is still managed by Yazi and can be terminated
--- when the functional-plugin task releases it before a GUI window appears.
---@param spec table
---@return boolean|nil launched
---@return any? err
function M.launch(spec)
	local argv = { ya.quote(spec.command) }
	for _, arg in ipairs(spec.args or {}) do argv[#argv + 1] = ya.quote(arg) end
	local command = table.concat(argv, " ")
	ya.emit("shell", { command, orphan = true })
	return true
end

return M
