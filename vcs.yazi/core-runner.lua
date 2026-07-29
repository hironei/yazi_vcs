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
	if line then
		lines[#lines + 1] = line
	end
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
	if spec.cwd then
		command:cwd(spec.cwd)
	end

	local child, spawn_err = command:spawn()
	if not child then
		return nil, spawn_err
	end

	local stdout, stderr = {}, {}
	local timeout = tonumber(timeout_ms or 0) or 0
	local deadline = timeout > 0 and (os.time() * 1000 + timeout) or nil
	local timed_out = false

	while true do
		local remaining = deadline and (deadline - os.time() * 1000) or 60000
		if remaining <= 0 then
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
			timed_out = true
			child:start_kill()
			break
		elseif event == 2 then
			break
		else
			break
		end
	end

	local status, wait_err = child:wait()
	if not status then
		return nil, wait_err
	end
	local result = {
		status = status,
		stdout = table.concat(stdout),
		stderr = table.concat(stderr),
	}
	if timed_out then
		result.status.success = false
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
	local ok, status, err = xpcall(function()
		local command = Command(spec.command)
			:arg(spec.args or {})
			:stdin(Command.INHERIT)
			:stdout(Command.INHERIT)
			:stderr(Command.INHERIT)
		if spec.cwd then
			command:cwd(spec.cwd)
		end
		local result, command_err = command:status()
		return result, command_err
	end, debug.traceback)
	permit:drop()
	if not ok then
		return nil, status
	end
	return status, err
end

return M
