-- config.lua
local M = {}

M.defaults = {
	detection = { priority = { "git", "svn" } },
	signs = {
		conflict = "C", missing = "!", deleted = "D", replaced = "R", modified = "M",
		property_modified = "P", added = "A", untracked = "?", locked = "L", external = "X",
		ignored = "I", clean = " ",
	},
	status = { order = 500, aggregate_directories = true, ignore_externals = true },
	info = { enabled = true, order = 600 },
	-- The editor always runs under ui.hide() and is always waited for
	-- (requirements §11.1/§11.4) — a non-blocking GUI editor would need a
	-- different commit flow entirely, so there is no `wait` toggle here.
	editor = { command = "nvim", args = {} },
	pager = { command = "less", args = { "-R" } },
	update = { git = { "git", "pull", "--ff-only" }, svn = { "svn", "update" } },
	-- Target scope is always selected > hovered > current (requirements
	-- §7); there is no per-operation scope-restriction knob.
	commit = { allow_empty_message = false, git_mode = "paths" },
	diff = {
		git_cli = { "git", "diff", "--", "{targets}" },
		svn_cli = { "svn", "diff", "--", "{targets}" },
		git_external = nil,
		svn_external = nil,
	},
	log = {
		git_cli = { "git", "log", "--decorate", "--oneline", "--graph", "--", "{targets}" },
		git_cli_all = { "git", "log", "--decorate", "--oneline", "--graph", "--all" },
		svn_cli = { "svn", "log", "--", "{targets}" },
		git_external = nil,
		svn_external = nil,
	},
	path = { external_style = "auto" },
	discard = { confirm = true, recursive_confirm_text = "revert" },
	runner = { timeout_ms = 30000 },
	git = {
		-- Force Push, Force Delete, auto-stash, and forced Switch are
		-- mandatory-safety exclusions (requirements.md §25), not
		-- configurable behavior — there is deliberately no toggle for any
		-- of them here.
		push = { default_remote = "origin", set_upstream_if_missing = true },
		branch = { show_remote = true },
		switch = { auto_track_remote = true },
	},
}

function M.deep_merge(defaults, overrides)
	if type(overrides) ~= "table" then return defaults end
	local result = {}
	local function is_array(value)
		for key in pairs(value) do
			if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
		end
		return true
	end
	local function copy(value)
		if type(value) ~= "table" then return value end
		local copied = {}
		for key, item in pairs(value) do copied[key] = copy(item) end
		return copied
	end
	for k, v in pairs(defaults) do
		if type(v) == "table" and type(overrides[k]) == "table" then
			result[k] = is_array(v) and copy(overrides[k]) or M.deep_merge(v, overrides[k])
		elseif overrides[k] == nil then result[k] = v else result[k] = overrides[k] end
	end
	for k, v in pairs(overrides) do if result[k] == nil then result[k] = copy(v) end end
	return result
end

function M.setup(user_config)
	require(".core-state").set_config(M.deep_merge(M.defaults, user_config or {}))
end

function M.get()
	return require(".core-state").get_config() or M.defaults
end

return M
