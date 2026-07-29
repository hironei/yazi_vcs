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
	editor = { command = "nvim", args = {}, wait = true },
	pager = { command = "less", args = { "-R" } },
	update = { git = { "git", "pull", "--ff-only" }, svn = { "svn", "update" } },
	commit = { default_scope = "selected", allow_empty_message = false, git_mode = "paths" },
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
	discard = { confirm = true, recursive_confirm_text = "revert", include_untracked = false },
	runner = { timeout_ms = 30000 },
	git = {
		push = { default_remote = "origin", set_upstream_if_missing = true, allow_force = false },
		branch = { show_remote = true, allow_force_delete = false, validate_name = true },
		switch = { auto_track_remote = true, auto_stash = false, allow_discard_changes = false },
	},
}

function M.deep_merge(defaults, overrides)
	if type(overrides) ~= "table" then return defaults end
	local result = {}
	for k, v in pairs(defaults) do
		if type(v) == "table" and type(overrides[k]) == "table" then
			result[k] = M.deep_merge(v, overrides[k])
		elseif overrides[k] == nil then result[k] = v else result[k] = overrides[k] end
	end
	for k, v in pairs(overrides) do if result[k] == nil then result[k] = v end end
	return result
end

function M.setup(user_config)
	require(".core-state").set_config(M.deep_merge(M.defaults, user_config or {}))
end

function M.get()
	return require(".core-state").get_config() or M.defaults
end

return M
