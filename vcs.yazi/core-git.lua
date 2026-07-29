-- core-git.lua
local M = {}
function M.current_branch_args() return { "branch", "--show-current" } end
function M.upstream_args() return { "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}" } end
function M.remote_args() return { "remote" } end
function M.branch_list_args(include_remote)
	local args = { "branch" }; if include_remote then args[#args + 1] = "--all" end
	args[#args + 1] = "--format=%(refname:short)%09%(HEAD)%09%(upstream:short)%09%(upstream:trackshort)%09%(refname)"; return args
end
function M.validate_name_input(name)
	name = tostring(name or ""); if name == "" then return false, "branch name is empty" end
	local first = name:sub(1, 1); if first == "@" or first == "-" then return false, "branch names beginning with @ or - are not accepted" end
	return true, nil
end
function M.check_ref_format_args(name) return { "check-ref-format", "--branch", name } end
function M.push_args(remote, branch, set_upstream)
	local args = { "push" }; if set_upstream then args[#args + 1] = "--set-upstream" end
	if remote then args[#args + 1] = remote end; if branch then args[#args + 1] = branch end; return args
end
function M.create_branch_args(name, start_point, switch)
	local args = switch and { "switch", "-c", name } or { "branch", name }; if start_point and start_point ~= "" then args[#args + 1] = start_point end; return args
end
function M.rename_branch_args(old_name, new_name)
	if old_name and old_name ~= "" then return { "branch", "-m", old_name, new_name } end; return { "branch", "-m", new_name }
end
function M.delete_branch_args(name) return { "branch", "-d", name } end
function M.switch_branch_args(name, remote, explicit_local)
	if remote and not explicit_local then return { "switch", "--track", remote } end
	if explicit_local then return { "switch", "-c", explicit_local, "--track", remote } end; return { "switch", name }
end
function M.parse_branches(stdout)
	local branches = {}
	for raw_line in tostring(stdout or ""):gmatch("[^\r\n]+") do
		local name, head, upstream, track, refname = raw_line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
		if name and name ~= "" then
			branches[#branches + 1] = {
				name = name, current = head == "*", upstream = upstream ~= "" and upstream or nil,
				tracking = track ~= "" and track or nil,
				remote = refname:match("^refs/remotes/") ~= nil,
				refname = refname,
			}
		end
	end
	return branches
end
function M.parse_lines(stdout)
	local result = {}
	for raw_line in tostring(stdout or ""):gmatch("[^\r\n]+") do
		local line = raw_line:gsub("^%s+", ""):gsub("%s+$", ""); if line ~= "" then result[#result + 1] = line end
	end
	return result
end
function M.find_branch(branches, name)
	for _, branch in ipairs(branches or {}) do if branch.name == name then return branch end end; return nil
end
return M
