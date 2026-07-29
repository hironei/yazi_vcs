-- core-status.lua
-- Pure status-code data and aggregation logic (requirements §8.2, §8.3,
-- §8.6). No Yazi API calls anywhere in this file, so it can be `require`d
-- and exercised under a plain `lua` interpreter for unit tests. The
-- Yazi-facing persistent storage built on top of this lives in
-- `core-state.lua`.
local M = {}

--- Status names ranked by display priority: higher wins when a single
--- path or an aggregating ancestor directory could show more than one
--- status at once (requirements §8.3). Every name has a unique number so
--- the number alone identifies the status.
---
--- `unknown` (not yet fetched) and `excluded` (bookkeeping only, for a
--- directory reported as wholly ignored by the VCS — see
--- `M.propagate_down`) are internal sentinels above every real status
--- and are never rendered directly; `excluded` is converted to `ignored`
--- wherever it would be shown. This "excluded" bookkeeping pattern is
--- adapted from the official `git.yazi` plugin (yazi-rs/plugins, MIT
--- license).
---
--- The base tiers follow requirements §8.3's priority list verbatim:
---   Conflict > Missing／Deleted > Modified／Replaced > Added／Untracked
---   > Locked／External > Ignored > Clean
--- `property_modified`'s tier, and the ordering *within* each tier
--- (missing vs. deleted, replaced vs. modified, added vs. untracked,
--- locked vs. external), are not specified there; both are
--- implementation decisions made here.
M.CODES = {
	unknown = 100,
	excluded = 99,

	conflict = 12,
	missing = 11,
	deleted = 10,
	replaced = 9,
	modified = 8,
	property_modified = 7, -- assumption: same tier as modified/replaced
	added = 6,
	untracked = 5,
	locked = 4,
	external = 3,
	ignored = 2,
	clean = 0,
}

--- Reverse lookup: priority number -> status name.
M.CODE_NAME = {}
for name, code in pairs(M.CODES) do
	M.CODE_NAME[code] = name
end

--- Priority number for `name`, or 0 ("clean") if `name` is unknown.
---@param name string
---@return integer
function M.priority(name)
	return M.CODES[name] or 0
end

--- Convert internal bookkeeping statuses to the status shown to users.
---@param name string?
---@return string?
function M.display_name(name)
	return name == "excluded" and "ignored" or name
end

--- Merge `changed` (relpath -> status name) into `into`, in place.
--- "clean" entries remove the key instead of storing it, keeping the
--- table sized to only the non-clean paths.
---@param into table<string,string>
---@param changed table<string,string>
function M.merge(into, changed)
	for relpath, name in pairs(changed) do
		if name == "clean" then
			into[relpath] = nil
		else
			into[relpath] = name
		end
	end
end

--- Roll each changed path's status up onto every ancestor directory
--- within the VCS root, keeping the highest-priority status at each
--- level (requirements §8.6). Paths whose status is "ignored" do not
--- contribute to their ancestors, so an ignored file inside an
--- otherwise-clean directory does not mark that directory ignored.
---
--- Adapted from the official `git.yazi` plugin's `bubble_up`
--- (yazi-rs/plugins, MIT license), generalized beyond Git's status set.
---@param changed table<string,string>  relpath -> status name
---@return table<string,string>         ancestor relpath -> status name (root's own "" key is never produced)
function M.bubble_up(changed)
	local new = {}
	for relpath, name in pairs(changed) do
		if name ~= "ignored" then
			local code = M.priority(name)
			local dir = relpath:match("^(.*)/[^/]+$")
			while dir do
				local prev = new[dir]
				if not prev or M.priority(prev) < code then
					new[dir] = name
				end
				dir = dir:match("^(.*)/[^/]+$")
			end
		end
	end
	return new
end

--- Decide, for directories the VCS reported as wholly ignored
--- (recognized by backends via a trailing "/" on the raw path), which
--- should be recorded as an "ignored" row in the currently-fetched
--- directory's listing, and whether the currently-fetched directory
--- itself sits inside one of them (in which case it is marked
--- "excluded" bookkeeping rather than walked further).
---
--- Adapted from the official `git.yazi` plugin's `propagate_down`
--- (yazi-rs/plugins, MIT license).
---@param excluded string[]  relpaths (no trailing slash) of wholly-ignored directories reported by this fetch
---@param cwd_rel string     relpath of the directory currently being fetched ("" for the VCS root itself)
---@return table<string,string> relpath -> status name; may include an entry keyed by `cwd_rel`
function M.propagate_down(excluded, cwd_rel)
	local new = {}
	for _, relpath in ipairs(excluded) do
		if relpath == cwd_rel or (cwd_rel ~= "" and (cwd_rel .. "/"):sub(1, #relpath + 1) == relpath .. "/") then
			new[cwd_rel] = "excluded"
		else
			local parent = relpath:match("^(.*)/[^/]+$") or ""
			if parent == cwd_rel then
				new[relpath] = "ignored"
			end
		end
	end
	return new
end

return M
