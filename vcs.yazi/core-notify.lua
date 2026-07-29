-- core-notify.lua
-- Notification formatting and dispatch (requirements §23).
--
-- `format` is pure and unit-tested directly; `M.info`/`M.warn`/`M.error`
-- call `ya.notify` and so only run inside Yazi.
local M = {}

local TITLE = "VCS"
local TIMEOUTS = { info = 3, warn = 6, error = 8 }

--- Render a printf-style message, collapsing embedded newlines to spaces
--- and trimming trailing whitespace so it fits Yazi's single-line
--- notification content. Falls back to the raw format string if the
--- arguments don't match it, rather than erroring inside a notification
--- call.
---@param s string
---@param ... any
---@return string
function M.format(s, ...)
	local ok, msg = pcall(string.format, s, ...)
	if not ok then
		msg = s
	end
	return (tostring(msg):gsub("[\r\n]+", " "):gsub("%s+$", ""))
end

---@param level "info"|"warn"|"error"
---@param s string
---@param ... any
local function send(level, s, ...)
	ya.notify({
		title = TITLE,
		content = M.format(s, ...),
		timeout = TIMEOUTS[level],
		level = level,
	})
end

---@param s string
---@param ... any
function M.info(s, ...)
	send("info", s, ...)
end

---@param s string
---@param ... any
function M.warn(s, ...)
	send("warn", s, ...)
end

---@param s string
---@param ... any
function M.error(s, ...)
	send("error", s, ...)
end

return M
