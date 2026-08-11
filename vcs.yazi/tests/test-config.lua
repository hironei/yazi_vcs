return function(t)
	local config = require("config")

	local merged = config.deep_merge(config.defaults, {
		status = {
			aggregate_directories = false,
			ignore_externals = false,
		},
		path = { external_style = "windows" },
		diff = { git_external = { command = "git", args = { "difftool" }, interactive = true } },
	})
	t.falsy(merged.status.aggregate_directories, "deep_merge preserves an explicit false override")
	t.falsy(merged.status.ignore_externals, "deep_merge preserves an explicit false override in a sibling key")
	t.eq(merged.status.order, config.defaults.status.order, "deep_merge retains unspecified sibling defaults")
	t.eq(merged.path.external_style, "windows", "external path style override is merged")
	t.eq(merged.diff.git_external.command, "git", "external diff configuration is merged")
	t.eq(merged.log.git_external, nil, "unspecified external log remains disabled")

	local replaced = config.deep_merge(config.defaults, {
		update = { git = { "git", "fetch" } },
		pager = { args = {} },
	})
	t.deep_eq(replaced.update.git, { "git", "fetch" }, "array-valued command settings are replaced")
	t.deep_eq(replaced.pager.args, {}, "an empty array clears default arguments")
end
