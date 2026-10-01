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

local function has_credential_assignment(text)
	for key in text:gmatch("([%w_%-]+)%s*[:=]") do
		if is_credential_key(key) then return true end
	end
	return false
end

local function is_dotted_diagnostic_parameter(parameter)
	return parameter:match("^%s*[%w_%-][%w_.%-]*%.[%w_.%-]+%s*:%s*%S") ~= nil
		and not has_credential_assignment(parameter)
end

local function unescape_diagnostic_text(parameter)
	local content = parameter:match('^%s*"(.*)"%s*$')
	local quote = content ~= nil and '"' or nil
	if content == nil then
		content = parameter:match("^%s*'(.*)'%s*$")
		quote = content ~= nil and "'" or nil
	end
	if content == nil then content = parameter end

	local output, position = {}, 1
	while position <= #content do
		local char = content:sub(position, position)
		if char == "\\" then
			local escaped = content:sub(position + 1, position + 1)
			if escaped ~= "\\" and escaped ~= '"' and escaped ~= "'" then return nil end
			output[#output + 1] = escaped
			position = position + 2
		elseif quote and char == quote then
			return nil
		else
			output[#output + 1] = char
			position = position + 1
		end
	end
	return table.concat(output)
end

local function is_unlabelled_diagnostic_parameter(parameter, previous, following, has_preceding_parameter)
	if not following or (not previous and not has_preceding_parameter) then return false end
	if previous and not previous:match("^%s*[%w_.%-]+%s*=") then return false end
	if not following:match("^%s*[%w_.%-]+%s*=") then return false end
	local content = unescape_diagnostic_text(parameter)
	if not content or not content:find("%s") then return false end
	for position = 1, #content do
		local char = content:sub(position, position)
		if not char:match("%w") and not char:match("%s") and char ~= "_" and char ~= "'" and char ~= '"'
			and char ~= "." and char ~= "-" and char ~= "\\" then return false end
	end
	local lower = content:lower():gsub("api[_%-]key", "apikey")
	for _, sensitive_word in ipairs({ "password", "passwd", "pwd", "token", "secret", "apikey", "auth", "bearer", "basic", "digest", "nonce", "response", "username", "realm", "opaque" }) do
		if lower:match("%f[%w]" .. sensitive_word .. "%f[%W]") then return false end
	end
	return true
end

local AUTHORIZATION_NAME = "authorization"
local authorization_delimiters
local DIGEST_PARAMETER_KEYS = {
	username = true,
	user = true,
	userhash = true,
	realm = true,
	nonce = true,
	uri = true,
	response = true,
	algorithm = true,
	cnonce = true,
	opaque = true,
	qop = true,
	nc = true,
	charset = true,
}

-- Lex one bounded line or value span once, sharing quote and escape rules for
-- single- and double-quoted diagnostics and Digest parameters.
local function lex_line(text, initial_quote)
	local states, delimiters, delimiter_lookup = {}, {}, {}
	local quote, quote_start, escaped = initial_quote, initial_quote and 0 or nil, false
	for position = 1, #text do
		local char = text:sub(position, position)
		local state = { quote = quote, quote_start = quote_start, opening = false, closing = false }
		if quote then
			if escaped then
				escaped = false
			elseif char == "\\" then
				escaped = true
			elseif char == quote then
				state.closing = true
				quote, quote_start = nil, nil
			end
		elseif char == '"' or (char == "'" and not text:sub(position - 1, position - 1):match("%w")) then
			state.opening = true
			quote, quote_start = char, position
		elseif char == "," or char == ";" or char == "&" then
			delimiters[#delimiters + 1] = position
			delimiter_lookup[position] = true
		end
		states[position] = state
	end
	return { states = states, delimiters = delimiters, delimiter_lookup = delimiter_lookup, quote = quote }
end

local function has_digest_parameter_after(line, start, quote_character)
	local delimiters = authorization_delimiters(line, start, #line + 1, quote_character)
	for _, separator in ipairs(delimiters) do
		local parameter_start = separator + 1
		while line:sub(parameter_start, parameter_start) == " " or line:sub(parameter_start, parameter_start) == "\t" do
			parameter_start = parameter_start + 1
		end
		local parameter = line:sub(parameter_start)
		local key = parameter:match("^([%w_.%-]+)%s*=")
		if key and DIGEST_PARAMETER_KEYS[key:lower()] == true then return true end
	end
	return false
end

local function find_authorization_headers(line)
	local headers, position = {}, 1
	local lex = lex_line(line)
	local current_header, quote_allows_authorization = nil, false
	while position <= #line do
		local char = line:sub(position, position)
		local state = lex.states[position]
		local in_quotes = state.quote ~= nil
		local is_authorization = line:sub(position, position + #AUTHORIZATION_NAME - 1):lower() == AUTHORIZATION_NAME
		if is_authorization and (not in_quotes or #headers == 0 or quote_allows_authorization) then
			local separator = position + #AUTHORIZATION_NAME
			while line:sub(separator, separator) == " " or line:sub(separator, separator) == "\t" do
				separator = separator + 1
			end
			if line:sub(separator, separator) == ":" then
				local value_start = separator + 1
				while line:sub(value_start, value_start) == " " or line:sub(value_start, value_start) == "\t" do
					value_start = value_start + 1
				end
				local digest_parent = current_header and (current_header.digest_parent
					or (current_header.is_digest
						and ((in_quotes and quote_allows_authorization)
							or current_header.diagnostic_context_seen
							or (not in_quotes and current_header.digest_parameter_seen and has_digest_parameter_after(line, value_start, false)))
						and current_header)) or nil
				current_header = {
					start = position,
					value_start = value_start,
					quoted_context = in_quotes,
					quote_character = state.quote,
					quote_wrapper = state.quote_start,
					digest_parent = digest_parent,
					is_digest = line:sub(value_start):match("^([Dd][Ii][Gg][Ee][Ss][Tt]%s+)") ~= nil,
					digest_parameter_seen = false,
					delimiter_seen = false,
					delimiter_segment_start = value_start,
				}
				headers[#headers + 1] = current_header
				quote_allows_authorization = false
				position = value_start
			else
				position = position + 1
			end
		elseif state.closing then
			if current_header and current_header.quoted_context and not current_header.wrapper_close
				and current_header.quote_wrapper == state.quote_start then
				current_header.wrapper_close = position
			end
			quote_allows_authorization = false
			position = position + 1
		elseif state.opening then
			if current_header then
				-- Ordinary scheme delimiters end its value; Digest delimiters may still separate parameters.
				if current_header.is_digest then
					local segment = line:sub(current_header.delimiter_segment_start, position - 1)
					quote_allows_authorization = current_header.delimiter_seen and segment:match("^%s*[%w_.%-]+%s*:") ~= nil
				else
					quote_allows_authorization = current_header.delimiter_seen
				end
			end
			position = position + 1
		elseif lex.delimiter_lookup[position] then
			if current_header then
				if current_header.is_digest then
					local segment = line:sub(current_header.delimiter_segment_start, position - 1)
					local digest_parameter = segment:gsub("^[Dd][Ii][Gg][Ee][Ss][Tt]%s+", "")
					if digest_parameter:match("^%s*[%w_.%-]+%s*=") then current_header.digest_parameter_seen = true end
					if is_dotted_diagnostic_parameter(segment) then current_header.diagnostic_context_seen = true end
				end
				current_header.delimiter_seen = true
				current_header.delimiter_segment_start = position + 1
			end
			position = position + 1
		else
			position = position + 1
		end
	end
	return headers
end

authorization_delimiters = function(line, start, stop, quote_character)
	local delimiters = {}
	local span = line:sub(start, stop - 1)
	if quote_character == false then quote_character = nil end
	local lex = lex_line(span, quote_character)
	for _, position in ipairs(lex.delimiters) do
		delimiters[#delimiters + 1] = start + position - 1
	end
	return delimiters
end

local function mask_digest_value(value, has_preceding_parameter)
	local digest_prefix = value:match("^([Dd][Ii][Gg][Ee][Ss][Tt]%s+)")
	if not digest_prefix then return nil end
	local parameter_text = value:sub(#digest_prefix + 1)
	local lex = lex_line(parameter_text)
	local segments, delimiters, segment_start = {}, {}, 1
	for _, delimiter in ipairs(lex.delimiters) do
		segments[#segments + 1] = parameter_text:sub(segment_start, delimiter - 1)
		delimiters[#delimiters + 1] = parameter_text:sub(delimiter, delimiter)
		segment_start = delimiter + 1
	end
	segments[#segments + 1] = parameter_text:sub(segment_start)
	local meaningful = {}
	for index, parameter in ipairs(segments) do
		if parameter:match("%S") then meaningful[#meaningful + 1] = index end
	end
	local meaningful_position = {}
	for index, segment_index in ipairs(meaningful) do meaningful_position[segment_index] = index end
	local output = {}
	for segment_index, parameter in ipairs(segments) do
		local position = meaningful_position[segment_index]
		if not position then
			output[#output + 1] = parameter
		else
			local previous = meaningful[position - 1] and segments[meaningful[position - 1]]
			local following = meaningful[position + 1] and segments[meaningful[position + 1]]
			if is_dotted_diagnostic_parameter(parameter)
				or is_unlabelled_diagnostic_parameter(
					parameter,
					previous,
					following,
					has_preceding_parameter and position == 1
				) then
				output[#output + 1] = parameter
			else
				output[#output + 1] = (parameter:match("^%s*") or "") .. REDACTED
			end
		end
		if delimiters[segment_index] then output[#output + 1] = delimiters[segment_index] end
	end
	return digest_prefix .. table.concat(output)
end

local function mask_authorization_line(line)
	local headers = find_authorization_headers(line)
	if #headers == 0 then return line end

	local output, cursor = {}, 1
	for index, header in ipairs(headers) do
		local next_header = headers[index + 1]
		local value_end = #line + 1
		local value = line:sub(header.value_start, next_header and next_header.start - 1 or #line)
		local is_digest = mask_digest_value(value) ~= nil
		if next_header then
			local delimiters = authorization_delimiters(line, header.value_start, next_header.start, header.quote_character)
			if is_digest then
				value_end = delimiters[#delimiters] or next_header.start
			else
				value_end = delimiters[1] or next_header.start
			end
		else
			if not is_digest then
				local delimiters = authorization_delimiters(line, header.value_start, #line + 1, header.quote_character)
				value_end = delimiters[1] or header.wrapper_close or (#line + 1)
			else
				value_end = header.wrapper_close or (#line + 1)
			end
		end
		if header.wrapper_close and header.wrapper_close < value_end then value_end = header.wrapper_close end

		output[#output + 1] = line:sub(cursor, header.value_start - 1)
		value = line:sub(header.value_start, value_end - 1)
		output[#output + 1] = mask_digest_value(value) or REDACTED
		cursor = value_end
		if header.digest_parent and (not next_header or next_header.digest_parent ~= header.digest_parent) then
			local tail_start = cursor
			if header.wrapper_close then
				output[#output + 1] = line:sub(cursor, header.wrapper_close)
				tail_start = header.wrapper_close + 1
			end
			local tail_end = next_header and next_header.start or (#line + 1)
			if next_header then
				local delimiters = authorization_delimiters(line, tail_start, next_header.start, false)
				tail_end = delimiters[#delimiters] or next_header.start
			end
			local digest_tail = line:sub(tail_start, tail_end - 1)
			local masked_tail = mask_digest_value("Digest " .. digest_tail, true)
			output[#output + 1] = masked_tail:sub(#"Digest " + 1)
			cursor = tail_end
		end
	end
	output[#output + 1] = line:sub(cursor)
	return table.concat(output)
end

local function mask_authorization_headers(text)
	local output, position = {}, 1
	while position <= #text do
		local line_end = text:find("[\r\n]", position)
		if not line_end then
			output[#output + 1] = mask_authorization_line(text:sub(position))
			position = #text + 1
		else
			local terminator_end = line_end
			if text:sub(line_end, line_end) == "\r" and text:sub(line_end + 1, line_end + 1) == "\n" then
				terminator_end = line_end + 1
			end
			output[#output + 1] = mask_authorization_line(text:sub(position, line_end - 1))
			output[#output + 1] = text:sub(line_end, terminator_end)
			position = terminator_end + 1
		end
	end
	return table.concat(output)
end

--- Mask credential-like values in arbitrary text before it reaches a log.
---@param text any
---@return string
function M.mask_text(text)
	text = tostring(text or "")
	-- Remove URL userinfo as a unit, including both username and password.
	text = text:gsub("([%a][%w+.-]*://)([^/%s]+)@", "%1" .. REDACTED .. "@")
	-- Authorization may use Basic, Bearer, Token, Negotiate, or another
	-- scheme. Scan each line independently so delimiter-separated headers are
	-- all masked without consuming CR/LF or unrelated diagnostic context.
	text = mask_authorization_headers(text)
	-- Bearer credentials do not necessarily have a key/value separator.
	text = text:gsub("([Bb][Ee][Aa][Rr][Ee][Rr]%s+)([^%s,;]+)", "%1" .. REDACTED)
	-- Cover query strings, environment-like assignments, and header-like text.
	text = text:gsub("([%w_%-]+)(%s*[:=]%s*)([^%s,;&]+)", function(key, separator, value)
		local authorization_scheme = normalized_credential_key(key) == "authorization"
			and (value:lower() == "bearer" or value:lower() == "basic" or value:lower() == "digest")
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

local function audit(spec, audit_config, status, started_at, stderr, failure_reason)
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
		error = failure_reason,
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
	local failure_reason = nil
	if timed_out then
		result.timed_out = true
		failure_reason = "command timed out"
		result.stderr = result.stderr ~= "" and result.stderr or "command timed out"
	end
	audit(spec, audit_config, result_status, started_at, result.stderr, failure_reason)
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
