return function(t)
	local old_ya = _G.ya
	_G.ya = { sync = function(fn) return fn end }
	package.loaded["core-state"] = nil
	local state_module = require("core-state")
	local state = {}

	state_module.set_vcs_spotters(state, { 42, 43 })
	t.eq(state_module.get_vcs_spotters(state)[2], 43, "state stores temporary Spotter IDs")
	t.truthy(state_module.is_vcs_spot_active(state), "state marks the VCS Spot active")
	state_module.set_vcs_spot_entries(state, {
		{ revision = "a1", message = "first" },
		{ revision = "b2", message = "second" },
	})
	t.eq(state_module.get_vcs_spot_row(state), 1, "state starts VCS Spot row selection at the first entry")
	t.eq(state_module.get_vcs_spot_entry(state, 1).revision, "a1", "state stores VCS Spot entries")
	state_module.move_vcs_spot_row(state, "next")
	t.eq(state_module.get_vcs_spot_row(state), 2, "state moves VCS Spot selection to the next entry")
	state_module.move_vcs_spot_row(state, "next")
	t.eq(state_module.get_vcs_spot_row(state), 1, "state wraps VCS Spot selection at the end")
	state_module.move_vcs_spot_row(state, "prev")
	t.eq(state_module.get_vcs_spot_row(state), 2, "state wraps VCS Spot selection at the beginning")
	state_module.clear_vcs_spotters(state)
	t.eq(state_module.get_vcs_spotters(state), nil, "state clears temporary Spotter IDs")
	t.eq(state_module.get_vcs_spot_entry(state, 1), nil, "state clears VCS Spot entries")
	t.eq(state_module.get_vcs_spot_row(state), nil, "state clears VCS Spot row selection")
	t.falsy(state_module.is_vcs_spot_active(state), "state clears the VCS Spot active flag with Spotters")
	state_module.set_vcs_spot_active(state, false)
	t.falsy(state_module.is_vcs_spot_active(state), "state clears the VCS Spot active flag")

	_G.ya = old_ya
end
