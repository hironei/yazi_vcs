-- backend-git.lua
-- Git backend: command construction and `status --porcelain=v2 -z` output
-- parsing (requirements §8.4, §8.4.1).
--
-- `status_args` and `parse_status` are pure (no Yazi API calls) and are
-- exercised directly by the unit tests, plus against a real `git` binary
-- via `io.popen` from the plain-Lua integration test. `M.fetch` is the
-- Yazi-facing adapter using `Command`, exercised only inside Yazi.
local M = {}

M.capabilities = { push = true, branch = true, switch = true }

--- Build the argument list for `git status` (requirements §8.4). Every
--- flag is there for a documented reason:
---   --no-optional-locks   don't contend with a `git` the user is running
---                         in another terminal (§27)
---   -c core.quotePath=    (kept even though `-z` already disables
---                         quoting on its own — see note below — cheap
---                         and harmless as a second guarantee)
---   --porcelain=v2 -z     stable machine format, NUL-delimited so a
---                         path can contain any byte including newlines;
---                         `-z` also disables path quoting, so Japanese
---                         and space-containing paths come through raw
---                         UTF-8 with no escaping to undo
---   --untracked-files=all list every untracked file individually
---                         instead of collapsing an untracked directory
---                         into one entry
---   --ignored=matching    without this, ignored paths are omitted
---                         entirely (verified empirically) and §8.2's
---                         Ignored state could never be shown
---@param paths string[]|nil  root-relative, forward-slash paths to limit the query to; nil/empty = whole repo
---@return string[]
function M.status_args(paths)
	local args = {
		"--no-optional-locks",
		"-c",
		"core.quotePath=",
		"status",
		"--porcelain=v2",
		"-z",
		"--untracked-files=all",
		"--ignored=matching",
	}
	if paths and #paths > 0 then
		args[#args + 1] = "--"
		for _, p in ipairs(paths) do
			args[#args + 1] = p
		end
	end
	return args
end

--- Split a NUL-delimited `git status -z` stream into fields. The final
--- empty field produced by a trailing NUL is dropped.
---@param stdout string
---@return string[]
local function split_nul(stdout)
	local fields = {}
	local start = 1
	while true do
		local nul = stdout:find("\0", start, true)
		if not nul then
			if start <= #stdout then
				fields[#fields + 1] = stdout:sub(start)
			end
			break
		end
		fields[#fields + 1] = stdout:sub(start, nul - 1)
		start = nul + 1
	end
	return fields
end

--- Classify a porcelain v2 XY pair into a unified status name
--- (requirements §8.2).
---@param x string single character: index/staged status
---@param y string single character: worktree status
---@return string
local function classify_xy(x, y)
	if x == "U" or y == "U" or (x == "A" and y == "A") or (x == "D" and y == "D") then
		return "conflict"
	elseif x == "D" or y == "D" then
		return "deleted"
	elseif x == "R" or x == "C" then
		return "replaced" -- copy detection needs -C/--find-copies, off by default; kept for robustness
	elseif y == "M" or y == "T" or x == "M" or x == "T" then
		return "modified"
	elseif x == "A" then
		return "added"
	end
	return "modified"
end

--- Parse `git status --porcelain=v2 -z ...` output. Rename/copy records
--- (leading "2") consume one extra NUL-delimited field for the original
--- path — verified empirically (requirements §8.4.1); a naive "one NUL
--- field per record" parser corrupts on the very next entry after a
--- rename.
---@param stdout string
---@return table<string,string> changed   relpath -> status name (as reported by git: forward-slash, root-relative)
---@return string[] excluded              relpaths of directories reported as wholly ignored (trailing slash stripped)
function M.parse_status(stdout)
	local fields = split_nul(stdout)
	local changed, excluded = {}, {}
	local i = 1
	while i <= #fields do
		local field = fields[i]
		local kind = field:sub(1, 1)

		if kind == "1" then
			local xy, path = field:match("^1 (..) %S+ %S+ %S+ %S+ %S+ %S+ (.*)$")
			if xy and path then
				changed[path] = classify_xy(xy:sub(1, 1), xy:sub(2, 2))
			end
			i = i + 1
		elseif kind == "2" then
			local xy, path = field:match("^2 (..) %S+ %S+ %S+ %S+ %S+ %S+ %S+ (.*)$")
			if xy and path then
				changed[path] = classify_xy(xy:sub(1, 1), xy:sub(2, 2))
			end
			i = i + 2 -- also consumes the orig-path field
		elseif kind == "u" then
			local path = field:match("^u .. %S+ %S+ %S+ %S+ %S+ %S+ %S+ %S+ (.*)$")
			if path then
				changed[path] = "conflict"
			end
			i = i + 1
		elseif kind == "?" then
			local path = field:match("^%? (.*)$")
			if path then
				changed[path] = "untracked"
			end
			i = i + 1
		elseif kind == "!" then
			local path = field:match("^! (.*)$")
			if path then
				local dir = path:match("^(.*)[/\\]$")
				if dir then
					excluded[#excluded + 1] = dir
				else
					changed[path] = "ignored"
				end
			end
			i = i + 1
		else
			-- Blank/unrecognized field (e.g. the harmless empty field a
			-- trailing NUL can produce) — skip rather than misparse.
			i = i + 1
		end
	end
	return changed, excluded
end

--- Run `git status` for `paths` against repository `root` and parse the
--- result.
---@param root string          absolute repository root; used as the command's cwd
---@param paths string[]|nil   root-relative paths to limit the query to
---@param options table|nil    backend options (currently unused)
---@return table<string,string>? changed
---@return string[]? excluded
---@return string? err
function M.fetch(root, paths, _options)
	local output, err = Command("git"):cwd(root):arg(M.status_args(paths)):output()
	if not output then
		return nil, nil, tostring(err)
	end
	if not output.status.success then
		return nil, nil, output.stderr
	end
	local changed, excluded = M.parse_status(output.stdout)
	return changed, excluded, nil
end

return M
