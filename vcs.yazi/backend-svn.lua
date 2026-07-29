-- backend-svn.lua
-- SVN backend: command construction and `status --xml` output parsing
-- (requirements §8.5).
--
-- `status_args` and `parse_status_xml` are pure (no Yazi API calls) and
-- are exercised directly by the unit tests, plus against a real `svn`
-- binary via `io.popen` from the plain-Lua integration test. `M.fetch`
-- is the Yazi-facing adapter using `Command`, exercised only inside
-- Yazi.
--
-- The XML schema assumed here is grounded in `svn status --xml` output
-- captured against a real SVN 1.14.5 working copy (not guessed): plain
-- normal/modified/added/deleted/missing/replaced/unversioned/ignored,
-- text conflict (item="conflicted"), tree conflict
-- (tree-conflicted="true"), property-only modification
-- (item="normal" props="modified"), and a repository lock (a `<lock>`
-- child element — NOT an attribute, contrary to an earlier assumption).
-- `obstructed`, `external`, and `incomplete` are grounded only in
-- `svn help status`'s documented status-letter table; they were not
-- reproduced against a live working copy — see requirements §26.4.
local path = require(".core-path")

local M = {}

M.capabilities = { push = false, branch = false, switch = false }

local ENTITIES = { amp = "&", lt = "<", gt = ">", quot = '"', apos = "'" }

--- Decode the XML escapes SVN emits in attribute values: the five named
--- entities and numeric character references (`&#20013;`, `&#x4E2D;`).
---@param s string
---@return string
local function decode_entities(s)
	return (
		s:gsub("&(#?[xX]?%w*);", function(code)
			if code:sub(1, 1) == "#" then
				local hex = code:sub(2, 2):lower() == "x"
				local digits = hex and code:sub(3) or code:sub(2)
				local n = tonumber(digits, hex and 16 or 10)
				return n and utf8.char(n) or ("&" .. code .. ";")
			end
			return ENTITIES[code] or ("&" .. code .. ";")
		end)
	)
end

--- Parse an opening tag's attribute text (everything after the tag name,
--- up to but not including the closing `>`) into a table. Attributes may
--- be spread across multiple lines — verified: real `svn status --xml`
--- output puts one attribute per line.
---@param tag_attrs string
---@return table<string,string>
local function parse_attrs(tag_attrs)
	local attrs = {}
	for name, value in tag_attrs:gmatch('([%w%-]+)%s*=%s*"([^"]*)"') do
		attrs[name] = decode_entities(value)
	end
	return attrs
end

--- Classify one `<entry>`'s attributes into a unified status name
--- (requirements §8.2, §8.3).
---@param attrs table<string,string>  the `<wc-status>` tag's attributes
---@param locked boolean              whether the entry has a `<lock>` child
---@return string
local function classify(attrs, locked)
	local item, props = attrs.item, attrs.props

	if attrs["tree-conflicted"] == "true" or item == "conflicted" or props == "conflicted" then
		return "conflict"
	elseif item == "missing" or item == "incomplete" then
		return "missing"
	elseif item == "obstructed" then
		return "conflict" -- "versioned item obstructed by a different kind"; not empirically verified
	elseif item == "deleted" then
		return "deleted"
	elseif item == "replaced" then
		return "replaced"
	elseif item == "modified" then
		return "modified"
	elseif item == "added" then
		return "added"
	elseif item == "unversioned" then
		return "untracked"
	elseif item == "ignored" then
		return "ignored"
	elseif item == "external" then
		return "external" -- not empirically verified
	elseif props == "modified" then
		return "property_modified"
	elseif locked then
		return "locked"
	end
	return "clean"
end

--- Build the argument list for `svn status` (requirements §8.5).
---   --no-ignore           without this, ignored paths are omitted
---                         entirely (verified empirically) and §8.2's
---                         Ignored state could never be shown
---   --ignore-externals    matches the git side's scope (§4.2 excludes
---                         externals handling) and keeps large working
---                         copies fast (§27)
---   --                    required: SVN parses a leading "-" in a path
---                         as an option otherwise (verified empirically
---                         with a file named "-dashfile.txt") — resolves
---                         requirements §26.4 item 3
---
--- `paths` must be root-relative, not absolute: verified empirically
--- that (unlike Git) SVN echoes each target back in the XML output
--- exactly as given — an absolute input path comes back as an absolute
--- (native-separator) output path, breaking the root-relative-key
--- assumption `parse_status_xml` and the rest of this plugin rely on.
---@param paths string[]|nil  root-relative, forward-slash paths to limit the query to; nil/empty = "."
---@return string[]
function M.status_args(paths)
	local args = { "status", "--xml", "--no-ignore", "--ignore-externals", "--" }
	if paths and #paths > 0 then
		for _, p in ipairs(paths) do
			args[#args + 1] = p
		end
	else
		args[#args + 1] = "."
	end
	return args
end

--- Parse the output of `svn status --xml --no-ignore --ignore-externals
--- ...` (requirements §8.5). Unlike Git, `svn status` does not recurse
--- into an unversioned or ignored directory by default (verified
--- empirically), so — unlike `backend-git.lua` — there is no
--- excluded/bubble-up special case to apply here: every `<entry>` maps
--- to exactly one `changed` row.
---@param xml string
---@return table<string,string> changed  relpath (forward-slash, root-relative) -> status name
function M.parse_status_xml(xml)
	local changed = {}
	for raw_path, body in xml:gmatch('<entry%s+path="(.-)"%s*>(.-)</entry>') do
		local relpath = decode_entities(raw_path)
		if relpath ~= "." then
			local tag_attrs = body:match("<wc%-status(.-)>")
			if tag_attrs then
				local attrs = parse_attrs(tag_attrs)
				local locked = body:find("<lock[%s>]") ~= nil
				changed[path.to_slash(relpath)] = classify(attrs, locked)
			end
		end
	end
	return changed
end

--- Run `svn status` for `paths` against working-copy root `root` and
--- parse the result.
---@param root string          absolute working-copy root; used as the command's cwd
---@param paths string[]|nil   root-relative paths to limit the query to
---@return table<string,string>? changed
---@return string? err
function M.fetch(root, paths)
	local output, err = Command("svn"):cwd(root):arg(M.status_args(paths)):output()
	if not output then
		return nil, tostring(err)
	end
	if not output.status.success then
		return nil, output.stderr
	end
	return M.parse_status_xml(output.stdout), nil
end

return M
