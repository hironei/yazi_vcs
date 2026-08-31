-- core-changes.lua
-- Pure helpers for the repository-wide VCS Changes View.
local M = {}

local HIDDEN = { clean = true, ignored = true, excluded = true }

--- Return changed status entries in deterministic path order.
---@param statuses table<string,string>
---@return table[] entries { path:string, status:string }
function M.list(statuses)
	local entries = {}
	for path, status in pairs(statuses or {}) do
		if status and not HIDDEN[status] then
			entries[#entries + 1] = { path = path, status = status }
		end
	end
	table.sort(entries, function(a, b) return a.path < b.path end)
	return entries
end

--- Split selected paths for Git's normal diff and no-index untracked diff.
---@param paths string[]
---@param statuses table<string,string>|nil
---@return string[] tracked
---@return string[] untracked
function M.partition(paths, statuses)
	local tracked, untracked = {}, {}
	for _, path in ipairs(paths or {}) do
		if statuses and statuses[path] == "untracked" then
			untracked[#untracked + 1] = path
		else
			tracked[#tracked + 1] = path
		end
	end
	return tracked, untracked
end

return M
