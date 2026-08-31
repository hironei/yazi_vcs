return function(t)
	local old_ya, old_ui = _G.ya, _G.ui
	local shared_state = {}
	_G.ui = { render = function() end }
	_G.ya = {
		sync = function(fn)
			return function(...) return fn(shared_state, ...) end
		end,
	}
	package.loaded["core-state"] = nil
	local state = require("core-state")
	t.falsy(state.log_preview_enabled(1), "log preview is disabled by default")
	t.truthy(state.toggle_log_preview(1), "toggle enables log preview for a tab")
	t.truthy(state.log_preview_enabled(1), "enabled state is readable for the same tab")
	t.falsy(state.log_preview_enabled(2), "tabs do not share log preview state")
	t.falsy(state.toggle_log_preview(1), "second toggle disables log preview")
	t.falsy(state.log_preview_enabled(1), "disabled state is readable after toggling off")
	_G.ya, _G.ui = old_ya, old_ui
end
