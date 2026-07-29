-- config.lua
-- Default configuration and merge logic (requirements §20, trimmed to
-- what Phase 1 — status display — actually consumes; later phases add
-- their own sections here as those features are built).
--
-- `M.defaults` and `M.deep_merge` are pure (no Yazi API calls) and are
-- exercised directly by the unit tests. `M.setup`/`M.get` defer their
-- `require(".core-state")` to inside the function body — not a
-- top-level `local` — specifically so that merely loading this file (to
-- reach the pure parts in a test) does not transitively hit
-- `core-state.lua`'s top-level `ya.sync` calls, which error outside a
-- running Yazi plugin.
local M = {}

M.defaults = {
	detection = {
		-- Order in which a Git root and an SVN root found at the exact
		-- same directory are disambiguated (requirements §6.4). Has no
		-- effect when only one is found, or when they're found at
		-- different depths — the one closer to the start directory
		-- always wins in that case.
		priority = { "git", "svn" },
	},

	signs = {
		conflict = "C",
		missing = "!",
		deleted = "D",
		replaced = "R",
		modified = "M",
		property_modified = "P",
		added = "A",
		untracked = "?",
		locked = "L",
		external = "X",
		ignored = "I",
		clean = " ",
	},

	status = {
		-- Entity child order (requirements §8.1). Below 1000 (the
		-- built-in "padding" child) puts the sign in the leading column.
		order = 500,
		aggregate_directories = true,
		ignore_externals = true,
	},
}

--- Deep-merge `overrides` into `defaults`, returning a new table.
--- Ported from the same pattern used by the official `sshfs.yazi`
--- plugin (uhs-robert/sshfs.yazi, MIT license).
---@param defaults table
---@param overrides table|nil
---@return table
function M.deep_merge(defaults, overrides)
	if type(overrides) ~= "table" then
		return defaults
	end
	local result = {}
	for k, v in pairs(defaults) do
		if type(v) == "table" and type(overrides[k]) == "table" then
			result[k] = M.deep_merge(v, overrides[k])
		elseif overrides[k] == nil then
			result[k] = v
		else
			result[k] = overrides[k]
		end
	end
	for k, v in pairs(overrides) do
		if result[k] == nil then
			result[k] = v
		end
	end
	return result
end

--- Merge `user_config` into the defaults and persist the result.
--- Called once from `main.lua`'s `setup`.
---@param user_config table|nil
function M.setup(user_config)
	require(".core-state").set_config(M.deep_merge(M.defaults, user_config or {}))
end

--- The active merged configuration.
---@return table
function M.get()
	return require(".core-state").get_config() or M.defaults
end

return M
