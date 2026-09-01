return function(t)
	local old_ya = _G.ya
	local calls = {}
	_G.ya = {
		notify = function(options) calls[#calls + 1] = options end,
	}
	package.loaded["core-notify"] = nil
	local notify = require("core-notify")
	notify.history("VCS log (latest 5)\nabc123 First line\ndef456 Second line")
	t.eq(#calls, 1, "history sends one notification")
	t.eq(calls[1].title, "VCS", "history uses the VCS title")
	t.eq(calls[1].content, "VCS log (latest 5)\nabc123 First line\ndef456 Second line", "history preserves line breaks")
	t.eq(calls[1].timeout, 8, "history uses a temporary timeout")
	t.eq(calls[1].level, "info", "history is informational")
	_G.ya = old_ya
end
