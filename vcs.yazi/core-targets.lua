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

--- Select file-operation sources: explicit selections first, then hover.
--- Unlike shared VCS scopes, these actions never fall back to cwd.
---@param selected table[]|nil
---@param hovered table|nil
---@return table[] sources
---@return "selected"|"hovered"|nil source
function M.choose_file_sources(selected, hovered)
	if selected and #selected > 0 then return selected, "selected" end
	if hovered then return { hovered }, "hovered" end
	return {}, nil
end

--- Require exactly one item for a rename; never discard an explicit selection.
---@param sources table[]
---@return table? source
---@return string? reason
function M.single_file_source(sources)
	if not sources or #sources == 0 then return nil, "no-target" end
	if #sources ~= 1 then return nil, "multiple" end
	return sources[1], nil
end

--- Validate one user-supplied basename.
---@param name string
---@return boolean valid
---@return string? reason
function M.validate_basename(name)
	name = tostring(name or "")
	if name == "" then return false, "name is empty" end
	if name == "." or name == ".." then return false, "dot path components are not allowed" end
	if name:find("[/\\%z\r\n]") then return false, "enter one filename without path separators or line breaks" end
	return true, nil
end

function M.rename_path(source, new_name)
	local valid, reason = M.validate_basename(new_name)
	if not valid then return nil, reason end
	local parent = tostring(source):match("^(.*)/[^/]+$")
	return parent and parent ~= "" and (parent .. "/" .. new_name) or new_name, nil
end

--- Plan a VCS move and preflight repository boundaries and target collisions.
--- `exists` is injected so the policy can be exercised without Yazi's fs API.
---@param root string
---@param sources table[] { path:string, is_dir:boolean }
---@param destination_dir string absolute directory path
---@param exists fun(path:string):boolean
---@param windows boolean?
---@return table? plan { paths:string[], destination:string, targets:string[] }
---@return table? reason
function M.plan_move(root, sources, destination_dir, exists, windows)
	if not sources or #sources == 0 then return nil, { code = "no-target" } end
	local destination_relative = Path.strip_prefix(root, destination_dir)
	if destination_relative == nil then return nil, { code = "outside", path = destination_dir } end
	if destination_relative == "" then destination_relative = "." end

	local relative, targets = {}, {}
	for _, source in ipairs(sources) do
		local source_relative = Path.strip_prefix(root, source.path)
		if source_relative == nil or source_relative == "" then
			return nil, { code = "outside", path = source.path }
		end
		local basename = Path.basename(source_relative)
		if not basename then return nil, { code = "invalid", path = source.path } end
		if source.is_dir and Path.is_within(source.path, destination_dir) then
			return nil, { code = "inside-source", path = source.path }
		end
		local target = Path.join_native(destination_dir, basename, windows == true)
		local target_exists = false
		if exists then
			local ok, result, detail = pcall(exists, target)
			if not ok then return nil, { code = "inspect-error", path = target, detail = result } end
			if result == nil then return nil, { code = "inspect-error", path = target, detail = detail } end
			target_exists = result == true
		end
		if Path.same(source.path, target) or target_exists then
			return nil, { code = "collision", path = target }
		end
		for _, previous in ipairs(targets) do
			if Path.same(previous, target) then return nil, { code = "duplicate", path = target } end
		end
		relative[#relative + 1] = source_relative
		targets[#targets + 1] = target
	end
	return { paths = relative, destination = destination_relative, targets = targets }, nil
end

--- Resolve one operation's path and repository scope from a context snapshot.
--- `detect` receives the directory from which VCS root discovery should start.
---@param selected string[]|nil
---@param cwd string|nil
---@param info table<string,boolean>|nil
---@param detect fun(start_path:string): "git"|"svn"|nil, string?
---@return table? scope
---@return table? reason
function M.resolve(selected, cwd, info, detect, options)
	options = options or {}
	if options.search and (not selected or #selected == 0) then
		return nil, { code = "no-target" }
	end
	local absolute, source, explicit = M.choose(selected, cwd)
	if #absolute == 0 then return nil, { code = "no-target" } end

	local kind, root, missing_path
	for _, path in ipairs(absolute) do
		local start = path
		if source == "selected" and not (info and info[path]) then start = Path.parent(path) end
		local found_kind, found_root = detect(start)
		if not found_kind or not found_root then
			missing_path = missing_path or path
		elseif not kind then
			kind, root = found_kind, found_root
		elseif kind ~= found_kind or not Path.same(root, found_root) then
			return nil, { code = "mixed", path = path }
		end
	end
	if not kind then return nil, { code = "not-found", path = missing_path or absolute[1] } end
	if missing_path then return nil, { code = "mixed", path = missing_path } end

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
		search = options.search == true,
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

--- Remove targets known to be untracked. Git restore/rm cannot operate on
--- these safely, and SVN revert/delete must not remove them implicitly.
---@param relative_paths string[]
---@param statuses table<string,string>|nil
---@return string[] kept
---@return string[] excluded
function M.exclude_untracked(relative_paths, statuses, versioned)
	local kept, excluded = {}, {}
	for _, path in ipairs(relative_paths) do
		if not (versioned and versioned[path]) and statuses and (statuses[path] == "untracked" or statuses[path] == "ignored" or statuses[path] == "excluded") then
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
