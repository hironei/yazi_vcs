-- tests/test-config.lua
return function(t)
	local config = require("config")

	local merged = config.deep_merge(config.defaults, {
		status = {
			aggregate_directories = false,
			ignore_externals = false,
		},
	})
	t.falsy(merged.status.aggregate_directories, "deep_merge preserves an explicit false override")
	t.falsy(merged.status.ignore_externals, "deep_merge preserves an explicit false override in a sibling key")
	t.eq(merged.status.order, config.defaults.status.order, "deep_merge retains unspecified sibling defaults")
