return function(t)
	local old_ya = _G.ya
	_G.ya = { sync = function(fn) return fn end }
	package.loaded["core-state"] = nil
	local state_module = require("core-state")
	local state = {}

	state_module.set_vcs_spotters(state, { 42, 43 })
	t.eq(state_module.get_vcs_spotters(state)[2], 43, "state stores temporary Spotter IDs")
	t.truthy(state_module.is_vcs_spot_active(state), "state marks the VCS Spot active")
	state_module.clear_vcs_spotters(state)
	t.eq(state_module.get_vcs_spotters(state), nil, "state clears temporary Spotter IDs")
	state_module.set_vcs_spot_active(state, false)
	t.falsy(state_module.is_vcs_spot_active(state), "state clears the VCS Spot active flag")

	_G.ya = old_ya
end
