-- tests/run.lua
-- Usage: cd vcs.yazi && lua tests/run.lua
--
-- Aliases Yazi's `require(".foo")` relative-module syntax (see
-- requirements §5.2) to plain Lua `require("foo")`, resolved via
-- `package.path` relative to the current directory — so this must be
-- run with `vcs.yazi/` as the working directory.
package.path = "./?.lua;./tests/?.lua;" .. package.path

local orig_require = require
_G.require = function(name)
	if name:sub(1, 1) == "." then
		name = name:sub(2)
	end
	return orig_require(name)
end

local t = require("support")

local suites = {
	"test-core-path",
	"test-core-status",
	"test-core-detector",
	"test-backend-git",
	"test-backend-svn",
}

for _, name in ipairs(suites) do
	print("== " .. name .. " ==")
	require(name)(t)
end

t.report()
