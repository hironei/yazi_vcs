-- core-vcs-info.lua
-- Pure parsing and formatting for repository metadata shown in the status bar.
local M = {}
local unpack_values = table.unpack or unpack

local function trim(value)
	return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function trim_slashes(value)
	return (trim(value):gsub("/+$", ""))
end

local function hex_byte(value, index)
	local pair = value:sub(index, index + 1)
	if not pair:match("^[0-9A-Fa-f][0-9A-Fa-f]$") then return nil end
	return tonumber(pair, 16)
end

-- Decode valid percent-encoded UTF-8 sequences while preserving URL syntax.
-- ASCII escapes (including spaces and reserved delimiters), malformed escapes,
-- and literal plus signs remain unchanged.
---@param value string
---@return string
function M.decode_percent_utf8(value)
	value = tostring(value or "")
	local result, index = {}, 1
	while index <= #value do
		local first = value:sub(index, index) == "%" and hex_byte(value, index + 1)
		local length
		if first and first >= 0xC2 and first <= 0xDF then
			length = 2
		elseif first and first >= 0xE0 and first <= 0xEF then
			length = 3
		elseif first and first >= 0xF0 and first <= 0xF4 then
			length = 4
		end

		local bytes = length and { first } or nil
		if bytes then
			for offset = 1, length - 1 do
				local percent = index + offset * 3
				local byte = value:sub(percent, percent) == "%" and hex_byte(value, percent + 1)
				if not byte or byte < 0x80 or byte > 0xBF then
					bytes = nil
					break
				end
				bytes[#bytes + 1] = byte
			end
		end
		if bytes then
			local second = bytes[2]
			if (first == 0xE0 and second < 0xA0)
				or (first == 0xED and second > 0x9F)
				or (first == 0xF0 and second < 0x90)
				or (first == 0xF4 and second > 0x8F) then
				bytes = nil
			end
		end
		if bytes then
			result[#result + 1] = string.char(unpack_values(bytes))
			index = index + length * 3
		else
			result[#result + 1] = value:sub(index, index)
			index = index + 1
		end
	end
	return table.concat(result)
end

function M.parse_git(stdout)
	local branch = trim(stdout)
	return { branch = branch ~= "" and branch or "HEAD (detached)" }
end

function M.parse_svn(url)
	return { url = trim(url) }
end

---@param last integer|nil
---@param now integer
---@param interval integer
---@return boolean
function M.refresh_due(last, now, interval)
	interval = tonumber(interval) or 0
	return interval <= 0 or not last or now - last >= interval
end

local function relative_path(relpath)
	relpath = tostring(relpath or ""):gsub("\\\\", "/"):gsub("^/+", "")
	return relpath == "." and "" or relpath
end

--- Build the URL for a path below an already-known SVN working-copy URL.
--- This is intentionally pure: the caller supplies the root URL and the
--- root-relative path computed from the local filesystem path.
---@param root_url string
---@param relpath string|nil  slash-separated, root-relative path; '.' is the root
---@return string
function M.svn_target_url(root_url, relpath)
	root_url = M.decode_percent_utf8(trim_slashes(root_url))
	relpath = M.decode_percent_utf8(relative_path(relpath))
	if root_url == "" then return relpath end
	return relpath == "" and root_url or root_url .. "/" .. relpath
end

--- Build the branch/path identifier used by the Git clipboard actions.
---@param branch string
---@param relpath string|nil  slash-separated, root-relative path; '.' is the root
---@return string
function M.git_target(branch, relpath)
	branch = trim(branch)
	relpath = relative_path(relpath)
	return relpath == "" and branch or branch .. "/" .. relpath
end

function M.format(kind, info, relpath)
	if not info then return nil end
	if kind == "git" and info.branch and info.branch ~= "" then
		return "(" .. info.branch .. ")"
	end
	if kind == "svn" and info.url and info.url ~= "" then
		return "(svn: " .. M.svn_target_url(info.url, relpath) .. ")"
	end
	return nil
end

return M
