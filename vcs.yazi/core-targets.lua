-- core-targets.lua
-- Pure target selection and VCS-root boundary checks (requirements §7).
local Path = require(".core-path")

local M = {}

--- Choose selected files first, then the current cwd.
---@param selected string[]|nil
---@param cwd string|nil
---@return string[] paths
---@return "selected"|"cwd"|nil source
---@return boolean explicit
function M.choose(selected, cwd)
	if selected and #selected > 0 then
		return selected, "selected", true
	end
	if cwd then
		return { cwd }, "cwd", false
	end
	return {}, nil, false
end

--- Resolve one operation's path and repository scope from a context snapshot.
--- `detect` receives the directory from which VCS root discovery should start.
---@param selected string[]|nil
---@param cwd string|nil
---@param info table<string,boolean>|nil
---@param detect fun(start_path:string): "git"|"svn"|nil, string?
---@return table? scope
---@return table? reason
function M.resolve(selected, cwd, info, detect)
	local absolute, source, explicit = M.choose(selected, cwd)
	if #absolute == 0 then return nil, { code = "no-target" } end

	local kind, root
	for _, path in ipairs(absolute) do
		local start = path
		if source == "selected" and not (info and info[path]) then start = Path.parent(path) end
		local found_kind, found_root = detect(start)
		if not found_kind or not found_root then
			return nil, { code = #absolute > 1 and "mixed" or "not-found", path = path }
		end
		if not kind then
			kind, root = found_kind, found_root
		elseif kind ~= found_kind or not Path.same(root, found_root) then
			return nil, { code = "mixed", path = path }
		end
	end

	local relative, invalid = M.relative(absolute, root)
	if not relative then return nil, { code = "outside", path = invalid } end
	local repository = false
	for _, path in ipairs(relative) do
		if path == "." then repository = true end
	end
	return {
		absolute = absolute,
		paths = relative,
		source = source,
		explicit = explicit,
		kind = kind,
		root = root,
		repository = repository,
		info = info or {},
	}, nil
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

--- Remove targets known to be ignored. `git add` refuses ignored paths
--- without `-f`, and SVN add skips svn:ignore'd paths by default; both
--- cases are reported to the user instead of silently failing/no-oping.
---@param relative_paths string[]
---@param statuses table<string,string>|nil
---@return string[] kept
---@return string[] excluded
function M.exclude_ignored(relative_paths, statuses)
	local kept, excluded = {}, {}
	for _, path in ipairs(relative_paths) do
		if statuses and (statuses[path] == "ignored" or statuses[path] == "excluded") then
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
