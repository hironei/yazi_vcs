-- core-commands.lua
-- Pure Git/SVN command argument builders for Phase 2.
local M = {}

local function append_targets(args, paths)
	if not paths or #paths == 0 then return args end
	args[#args + 1] = "--"
	for _, path in ipairs(paths or {}) do
		args[#args + 1] = path
	end
	return args
end

function M.git_update()
	return { "pull", "--ff-only" }
end

function M.svn_update(paths)
	local args = { "update" }
	if paths and #paths > 0 then
		append_targets(args, paths)
	end
	return args
end

function M.git_commit(paths, mode)
	local args = { "commit" }
	if mode ~= "staged" then
		append_targets(args, paths)
	end
	return args
end

function M.svn_commit(paths)
	return append_targets({ "commit" }, paths)
end

local function svn_literal_source(path)
	path = tostring(path)
	-- SVN parses a final @REV as a peg revision, even for local paths.
	-- Appending @ forces an ambiguous at-sign path to remain literal.
	return path:find("@", 1, true) and (path .. "@") or path
end

function M.git_diff(paths)
	return append_targets({ "--no-pager", "diff" }, paths)
end

function M.git_diff_no_index(empty_path, target)
	return { "--no-pager", "diff", "--no-index", "--", empty_path, target }
end

function M.svn_diff(paths)
	return append_targets({ "diff" }, paths)
end

function M.git_log(paths)
	local args = { "--no-pager", "log", "--decorate", "--oneline", "--graph" }
	if paths and #paths > 0 then
		return append_targets(args, paths)
	end
	args[#args + 1] = "--all"
	return args
end

function M.svn_log(paths)
	return append_targets({ "log" }, paths)
end

function M.git_add(paths)
	return append_targets({ "add" }, paths)
end

function M.svn_add(paths)
	return append_targets({ "add" }, paths)
end

function M.svn_move(paths, destination)
	local args = { "move", "--" }
	for _, path in ipairs(paths or {}) do args[#args + 1] = svn_literal_source(path) end
	-- `DST` is a local output path, not a peg-revision source, so preserve it
	-- exactly (including a trailing @ in the requested filename).
	args[#args + 1] = destination
	return args
end

function M.git_delete(paths)
	return append_targets({ "--literal-pathspecs", "rm", "-r" }, paths)
end

function M.svn_delete(paths)
	local args = { "delete", "--" }
	for _, path in ipairs(paths or {}) do args[#args + 1] = svn_literal_source(path) end
	return args
end

function M.git_discard(paths)
	return append_targets({ "restore" }, paths)
end

function M.svn_discard(paths, recursive)
	local args = { "revert" }
	if recursive then
		args[#args + 1] = "--depth=infinity"
	end
	return append_targets(args, paths)
end

return M
