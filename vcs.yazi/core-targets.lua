-- core-targets.lua
-- Pure target selection and VCS-root boundary checks (requirements §7).
local Path = require(".core-path")

local M = {}

--- Choose selected files first, then the hovered file, then the current cwd.
---@param selected string[]|nil
---@param hovered string|nil
---@param cwd string|nil
---@return string[] paths
---@return "selected"|"hovered"|"current"|nil scope
function M.choose(selected, hovered, cwd)
	if selected and #selected > 0 then
		return selected, "selected"
	end
	if hovered then
		return { hovered }, "hovered"
	end
	if cwd then
		return { cwd }, "current"
	end
	return {}, nil
end

--- Convert absolute paths to root-relative CLI paths. The root itself is '.'.
--- No path outside the root is returned; the second result explains the error.
---@param absolute_paths string[]
---@param root string
---@return string[]|nil relative
---@return string? invalid_path
function M.relative(absolute_paths, root)
	local relative = {}
	for _, absolute in ipairs(absolute_paths) do
		local rel = Path.strip_prefix(root, absolute)
		if rel == nil then
			return nil, absolute
		end
		relative[#relative + 1] = rel == "" and "." or rel
	end
	return relative, nil
end

--- Remove targets known to be untracked. Git restore cannot operate on these,
--- and SVN revert must never be used as an untracked-file deletion mechanism.
---@param relative_paths string[]
---@param statuses table<string,string>|nil
---@return string[] kept
---@return string[] excluded
function M.exclude_untracked(relative_paths, statuses)
	local kept, excluded = {}, {}
	for _, path in ipairs(relative_paths) do
		if statuses and (statuses[path] == "untracked" or statuses[path] == "ignored" or statuses[path] == "excluded") then
			excluded[#excluded + 1] = path
		else
			kept[#kept + 1] = path
		end
	end
	return kept, excluded
end

--- Render a compact, newline-separated target list for confirmation dialogs.
---@param paths string[]
---@return string
function M.describe(paths)
	local lines = {}
	for _, path in ipairs(paths) do
		lines[#lines + 1] = "  " .. path
	end
	return table.concat(lines, "\n")
end

return M
