return function(t)
	local old_ya = _G.ya
	_G.ya = { sync = function(fn) return fn end }
	package.loaded["core-state"] = nil
	local state_module = require("core-state")
	local state = {}

	state_module.set_vcs_spotter(state, 42)
	t.eq(state_module.get_vcs_spotter(state), 42, "state stores the temporary Spotter ID")
	t.truthy(state_module.is_vcs_spot_active(state), "state marks the VCS Spot active")
	state_module.clear_vcs_spotter(state)
	t.eq(state_module.get_vcs_spotter(state), nil, "state clears the temporary Spotter ID")
	state_module.set_vcs_spot_active(state, false)
	t.falsy(state_module.is_vcs_spot_active(state), "state clears the VCS Spot active flag")

	_G.ya = old_ya
end
