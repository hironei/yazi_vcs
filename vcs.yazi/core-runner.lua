-- core-runner.lua
-- External command execution. Command construction helpers are pure; the
-- execution functions require Yazi and are called only from async actions.
local M = {}
local REDACTED = "[REDACTED]"

local CREDENTIAL_KEYS = {
	password = true,
	passwd = true,
	pwd = true,
	token = true,
	accesstoken = true,
	refreshtoken = true,
	apikey = true,
	secret = true,
	clientsecret = true,
	authorization = true,
	auth = true,
}

local function normalized_credential_key(key)
	return tostring(key):lower():gsub("[_%-]", "")
end

local function is_credential_key(key)
	local normalized = normalized_credential_key(key)
	if CREDENTIAL_KEYS[normalized] == true then return true end
	return normalized:find("token", 1, true) ~= nil
		or normalized:find("secret", 1, true) ~= nil
		or normalized:find("password", 1, true) ~= nil
		or normalized:find("passwd", 1, true) ~= nil
		or normalized:find("apikey", 1, true) ~= nil
		or normalized:find("authorization", 1, true) ~= nil
end

--- Mask credential-like values in arbitrary text before it reaches a log.
---@param text any
---@return string
function M.mask_text(text)
	text = tostring(text or "")
	-- Remove URL userinfo as a unit, including both username and password.
	text = text:gsub("([%a][%w+.-]*://)([^/%s]+)@", "%1" .. REDACTED .. "@")
	-- Authorization headers carry a scheme and a value in one token sequence.
	text = text:gsub("([Aa][Uu][Tt][Hh][Oo][Rr][Ii][Zz][Aa][Tt][Ii][Oo][Nn])(%s*:%s*)([Bb][Aa][Ss][Ii][Cc])(%s+)([^%s,;&]+)", function(key, separator, scheme, spaces)
		return key .. separator .. scheme .. spaces .. REDACTED
	end)
	-- Bearer and Basic credentials do not necessarily have a key/value separator.
	text = text:gsub("([Bb][Ee][Aa][Rr][Ee][Rr]%s+)([^%s,;]+)", "%1" .. REDACTED)
	text = text:gsub("([Bb][Aa][Ss][Ii][Cc]%s+)([^%s,;]+)", "%1" .. REDACTED)
	-- Cover query strings, environment-like assignments, and header-like text.
	text = text:gsub("([%w_%-]+)(%s*[:=]%s*)([^%s,;&]+)", function(key, separator, value)
		local authorization_scheme = normalized_credential_key(key) == "authorization"
			and (value:lower() == "bearer" or value:lower() == "basic")
		return is_credential_key(key) and not authorization_scheme and key .. separator .. REDACTED or key .. separator .. value
	end)
	return text
end

--- Mask argument values following standalone credential flags as well as
--- credential assignments embedded in each argument.
---@param args string[]|nil
---@return string[]
function M.mask_args(args)
	local masked, redact_next = {}, false
	for _, arg in ipairs(args or {}) do
		local text = tostring(arg)
		if redact_next and not text:match("^%-%-") then
			masked[#masked + 1] = REDACTED
			redact_next = false
		else
			masked[#masked + 1] = M.mask_text(text)
			redact_next = false
		end
		local flag = text:gsub("^%-%-?", "")
		redact_next = is_credential_key(flag) and not text:find("=", 1, true) and not text:find(":", 1, true)
	end
	return masked
end

local function json_quote(value)
	local text = tostring(value or "")
	local escaped = {}
	for index = 1, #text do
		local char = text:sub(index, index)
		local byte = string.byte(char)
		if char == "\\" then escaped[#escaped + 1] = "\\\\"
		elseif char == '"' then escaped[#escaped + 1] = '\\"'
		elseif char == "\b" then escaped[#escaped + 1] = "\\b"
		elseif char == "\f" then escaped[#escaped + 1] = "\\f"
		elseif char == "\n" then escaped[#escaped + 1] = "\\n"
		elseif char == "\r" then escaped[#escaped + 1] = "\\r"
		elseif char == "\t" then escaped[#escaped + 1] = "\\t"
		elseif byte < 32 then escaped[#escaped + 1] = string.format("\\u%04x", byte)
		else escaped[#escaped + 1] = char end
	end
	return '"' .. table.concat(escaped) .. '"'
end

local function json_array(values)
	local quoted = {}
	for _, value in ipairs(values or {}) do quoted[#quoted + 1] = json_quote(value) end
	return "[" .. table.concat(quoted, ",") .. "]"
end

--- Format a structured, already-masked audit record for `ya.dbg`.
---@param record table
---@return string
function M.audit_message(record)
	local exit_code = record.exit_code == nil and "null" or tostring(record.exit_code)
	local duration_ms = tonumber(record.duration_ms or 0) or 0
	return "vcs audit {" .. table.concat({
		"\"command\":" .. json_quote(M.mask_text(record.command)),
		"\"args\":" .. json_array(M.mask_args(record.args)),
		"\"cwd\":" .. json_quote(M.mask_text(record.cwd)),
		"\"exit_code\":" .. exit_code,
		"\"duration_ms\":" .. tostring(math.max(0, math.floor(duration_ms))),
		"\"stderr\":" .. (record.stderr == nil and "null" or json_quote(M.mask_text(record.stderr))),
		"\"error\":" .. (record.error == nil and "null" or json_quote(M.mask_text(record.error))),
	}, ",") .. "}"
end

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

local function join_lines(lines)
	local chunks = {}
	for index, line in ipairs(lines) do
		chunks[#chunks + 1] = line
		-- Yazi's read_line_with returns the line terminator when one was
		-- read. Keep it intact, while tolerating test doubles and an
		-- unterminated final record without producing doubled newlines.
		if index < #lines and line:sub(-1) ~= "\n" then chunks[#chunks + 1] = "\n" end
	end
	return table.concat(chunks)
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

local function audit_enabled(audit_config)
	return type(audit_config) == "table" and audit_config.enabled == true
end

local function audit(spec, audit_config, status, started_at, stderr, error)
	if not audit_enabled(audit_config) or type(ya) ~= "table" or type(ya.dbg) ~= "function" then return end
	local exit_code = status and status.code or nil
	local duration_ms = now_ms() - started_at
	pcall(ya.dbg, M.audit_message({
		command = spec.command,
		args = spec.args,
		cwd = spec.cwd,
		exit_code = exit_code,
		duration_ms = duration_ms,
		stderr = stderr,
		error = error,
	}))
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
---@param audit_config table|nil
---@return table|nil output { status={success,code}, stdout, stderr }
---@return any? err
function M.run(spec, timeout_ms, audit_config)
	local started_at = now_ms()
	local command = Command(spec.command)
		:arg(spec.args or {})
		:stdin(Command.NULL)
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
	if spec.cwd then command:cwd(spec.cwd) end

	local child, spawn_err = command:spawn()
	if not child then
		audit(spec, audit_config, nil, started_at, nil, spawn_err)
		return nil, spawn_err
	end

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
	if not status then
		audit(spec, audit_config, nil, started_at, nil, wait_err)
		return nil, wait_err
	end
	-- Never write into `status` itself: it's the `Status` userdata `Child:wait()`
	-- returns, which every other call site only ever reads (backend-git.lua,
	-- backend-svn.lua) — on a timeout, substitute a plain table with the same
	-- `success`/`code` shape instead of mutating a value we don't own.
	local result_status = timed_out and { success = false, code = status.code } or status
	-- Yazi returns lines including a terminator when one was read. Join
	-- without adding a second terminator; test doubles and an unterminated
	-- final record are normalized to the same newline-delimited form.
	local result = { status = result_status, stdout = join_lines(stdout), stderr = join_lines(stderr) }
	if timed_out then
		result.timed_out = true
		result.stderr = result.stderr ~= "" and result.stderr or "command timed out"
	end
	audit(spec, audit_config, result_status, started_at, result.stderr)
	return result, nil
end

--- Run an editor, pager, or other interactive command while Yazi's terminal is
--- hidden. The permit is always released, including command failures.
---@param spec table
---@param audit_config table|nil
---@return table|nil status
---@return any? err
function M.interactive(spec, audit_config)
	local started_at = now_ms()
	local permit = ui.hide()
	-- Keep the protected region limited to command construction/execution. The
	-- permit is dropped outside it so Lua errors cannot leave Yazi hidden.
	local ok, status, err = pcall(function()
		local command = Command(spec.command)
			:arg(spec.args or {})
			:stdin(Command.INHERIT)
			:stdout(Command.INHERIT)
			:stderr(Command.INHERIT)
		if spec.cwd then command:cwd(spec.cwd) end
		return command:status()
	end)
	permit:drop()
	if not ok then
		audit(spec, audit_config, nil, started_at, nil, status)
		return nil, status
	end
	audit(spec, audit_config, status, started_at, nil, err)
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
