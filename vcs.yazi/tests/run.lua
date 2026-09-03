package.path = "./?.lua;./tests/?.lua;" .. package.path
local orig_require = require
_G.require = function(name)
	if name:sub(1, 1) == "." then name = name:sub(2) end
	return orig_require(name)
end
local t = require("support")
local suites = {
	"test-config", "test-core-path", "test-core-status", "test-core-detector", "test-core-targets",
	"test-core-commands", "test-core-runner", "test-core-git", "test-core-external", "test-support", "test-backend-git",
	"test-backend-svn", "test-operations", "test-git-phase3",
	"test-core-vcs-info", "test-core-fetcher", "test-core-context", "test-core-changes",
	"test-core-temp", "test-core-log-preview", "test-core-preview", "test-core-notify", "test-core-state",
}
for _, name in ipairs(suites) do
	print("== " .. name .. " ==")
	require(name)(t)
end
t.report()
