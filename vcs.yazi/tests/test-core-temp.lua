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

	do
		local old_fs, old_url = _G.fs, _G.Url
		local calls = {}
		_G.Url = function(path) return path end
		_G.fs = {
			unique = function(kind, requested)
				calls.unique = { kind, requested }
				return requested .. "-reserved"
			end,
			write = function(path, content)
				calls.write = { path, content }
				return true
			end,
		}
		local ok, err = pcall(function()
			local written = temp.write("candidate.tmp", "payload")
			t.eq(written, "candidate.tmp-reserved", "temporary write returns the reserved unique path")
			t.deep_eq(calls.unique, { "file", "candidate.tmp" }, "temporary write reserves a file through fs.unique")
			t.deep_eq(calls.write, { "candidate.tmp-reserved", "payload" }, "temporary write uses the reserved path")
		end)
		_G.fs, _G.Url = old_fs, old_url
		if not ok then error(err, 0) end
	end

	do
		local old_fs, old_url = _G.fs, _G.Url
		local calls = {}
		_G.Url = function(path) return path end
		_G.fs = {
			unique = function(_, requested) return requested .. "-reserved" end,
			write = function() return true end,
			remove = function(_, path) calls.removed = path; return true end,
		}
		local runner = {
			interactive = function(spec, audit_config)
				calls.spec = spec
				calls.audit = audit_config
				return { success = true, code = 0 }
			end,
		}
		local ok, err = pcall(function()
			local shown = temp.display(
				"diff output",
				{
					pager = { command = "less", args = {} },
					editor = { command = "nvim", args = {} },
					runner = { audit = { enabled = true } },
				},
				runner
			)
			t.truthy(shown, "temporary display succeeds")
			t.eq(calls.spec.command, "less", "temporary display uses the configured pager")
			t.truthy(calls.spec.args[1]:match("vcs%-output"), "temporary display passes its output file")
			t.truthy(calls.audit.enabled, "temporary display passes runner audit configuration")
			t.truthy(calls.removed, "temporary display removes the output file")
		end)
		_G.fs, _G.Url = old_fs, old_url
		if not ok then error(err, 0) end
	end
end
