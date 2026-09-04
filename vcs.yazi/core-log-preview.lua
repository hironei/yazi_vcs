-- core-log-preview.lua
-- Pure command construction and one-line history formatting for the log
-- preview. VCS process execution remains in main.lua through core-runner.
local M = {}

M.LIMIT = 5

function M.message(kind, reason, detail)
	if reason == "no-item" then return "No hovered item." end
	if reason == "outside-repository" then return "No Git or SVN repository." end
	if reason == "outside-root" then return "The hovered item is outside the repository." end
	if reason == "untracked" then return "Untracked files have no history." end
	if reason == "empty" then return "No history for the hovered item." end
	if reason == "command-failed" then return tostring(kind or "VCS"):upper() .. " log failed: " .. tostring(detail or "unknown error") end
	return tostring(detail or "Unable to load VCS history.")
end

function M.git_args(relative_path)
	return {
		"--no-pager",
		"log",
		"-n",
		tostring(M.LIMIT),
		"--date=short",
		"--format=%h%x09%ad%x09%s",
		"--",
		relative_path == "" and "." or relative_path,
	}
end

function M.svn_args(relative_path)
	return { "log", "--xml", "-l", tostring(M.LIMIT), "--", relative_path == "" and "." or relative_path }
end

local function trim(value)
	return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function first_non_empty_line(value)
	for raw_line in tostring(value or ""):gmatch("[^\r\n]+") do
		local line = trim(raw_line)
		if line ~= "" then return line end
	end
	return ""
end

function M.parse_git(stdout)
	local entries = {}
	for raw_line in tostring(stdout or ""):gmatch("[^\r\n]+") do
		local line = trim(raw_line)
		local revision, date, subject = line:match("^(%S+)%s+(%S+)%s+(.*)$")
		if revision and date then
			entries[#entries + 1] = { date = trim(date), revision = trim(revision), message = trim(subject) }
			if #entries == M.LIMIT then break end
		end
	end
	return entries
end

local ENTITIES = { amp = "&", lt = "<", gt = ">", quot = '"', apos = "'" }

local function decode_entities(value)
	return tostring(value or ""):gsub("&(#?[xX]?%w*);", function(code)
		if code:sub(1, 1) == "#" then
			local hexadecimal = code:sub(2, 2):lower() == "x"
			local digits = hexadecimal and code:sub(3) or code:sub(2)
			local number = tonumber(digits, hexadecimal and 16 or 10)
			return number and utf8.char(number) or ("&" .. code .. ";")
		end
		return ENTITIES[code] or ("&" .. code .. ";")
	end)
end

local function attrs(text)
	local result = {}
	for name, value in tostring(text or ""):gmatch('([%w%-]+)%s*=%s*"([^"]*)"') do
		result[name] = decode_entities(value)
	end
	return result
end

local function tag(body, name)
	return decode_entities(tostring(body or ""):match("<" .. name .. ">(.-)</" .. name .. ">") or "")
end

function M.parse_svn(xml)
	local entries = {}
	for raw_attrs, body in tostring(xml or ""):gmatch("<logentry%s+([^>]-)>%s*(.-)%s*</logentry>") do
		local entry_attrs = attrs(raw_attrs)
		local revision = entry_attrs.revision or "?"
		local author = trim(tag(body, "author"))
		if author == "" then author = "-" end
		local date = trim(tag(body, "date")):match("^(%d%d%d%d%-%d%d%-%d%d)") or "-"
		local message = first_non_empty_line(tag(body, "msg"))
		if message == "" then message = "(no message)" end
		entries[#entries + 1] = { author = author, date = date, message = message, revision = "r" .. revision }
		if #entries == M.LIMIT then break end
	end
	return entries
end

function M.args(kind, relative_path)
	if kind == "git" then return M.git_args(relative_path) end
	if kind == "svn" then return M.svn_args(relative_path) end
	return nil
end

function M.parse(kind, stdout)
	if kind == "git" then return M.parse_git(stdout) end
	if kind == "svn" then return M.parse_svn(stdout) end
	return {}
end

function M.format(entry)
	if type(entry) ~= "table" then return tostring(entry or "") end
	if entry.author then
		return string.format("%s %s %s %s", entry.revision or "?", entry.author, entry.date or "-", entry.message or "")
	end
	return string.format("%s %s", entry.revision or "?", entry.message or "")
end

function M.table_rows(entries, fallback)
	local rows = { { "Date", "Revision", "Message" } }
	if #entries == 0 then
		rows[#rows + 1] = { "-", "-", fallback or "No history for the hovered item." }
		return rows
	end
	for _, entry in ipairs(entries) do
		rows[#rows + 1] = {
			tostring(entry.date or "-"),
			tostring(entry.revision or "-"),
			tostring(entry.message or "-"),
		}
	end
	return rows
end

return M
