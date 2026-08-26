return function(t)
	local temp = require("core-temp")
	local first, first_err = temp.path("vcs-test", "")
	local second, second_err = temp.path("vcs-test", "")
	t.truthy(first, "temporary path allocation succeeds: " .. tostring(first_err))
	t.truthy(second, "second temporary path allocation succeeds: " .. tostring(second_err))
	if not first or not second then return end
	t.truthy(first ~= second, "temporary paths are unique")
	if package.config:sub(1, 1) == "\\" then
		t.truthy(first:match("^%a:[/\\]") or first:match("^\\\\"), "Windows temporary path is native and absolute")
	end
end
