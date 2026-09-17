return function(t)
	local saved_modules, names = {}, {
		"config", "core-detector", "core-external", "core-notify", "core-path", "core-runner",
		"core-scope", "core-state", "core-targets", "core-changes", "core-log-preview",
		"core-commands", "core-temp", "core-versioned-path", "backend-git", "backend-svn",
	}
	local copied, runner_calls, notifications = {}, {}, {}
	local cfg = { runner = { timeout_ms = 1000 }, detection = { priority = { "git", "svn" } } }
	local function stub(name, value)
		saved_modules[name] = package.loaded[name]
		package.loaded[name] = value
	end

	stub("config", { get = function() return cfg end })
	stub("core-detector", {})
	stub("core-external", {})
	stub("core-notify", {
		info = function(...) notifications[#notifications + 1] = { ... } end,
		warn = function(...) notifications[#notifications + 1] = { ... } end,
		error = function(...) notifications[#notifications + 1] = { ... } end,
	})
	stub("core-path", {})
	stub("core-runner", {
		run = function(spec)
			runner_calls[#runner_calls + 1] = spec
			return { status = { success = true }, stdout = "42\n", stderr = "" }, nil
		end,
		summary = function(value) return tostring(value or "") end,
		error_text = function(_, err) return tostring(err or "unknown error") end,
	})
	stub("core-scope", {
		resolve_or_notify = function()
			return {
				kind = "svn",
				root = "/wc",
				paths = { "資料.txt" },
				absolute = { "/wc/資料.txt" },
			}
		end,
	})
	stub("core-state", {
		info_of = function() return { kind = "svn", data = { url = "https://host/svn/%E6%97%A5%E6%9C%AC" } } end,
	})
	stub("core-targets", {})
	stub("core-changes", {})
	stub("core-log-preview", {})
	stub("core-commands", {})
	stub("core-temp", {})
	stub("core-versioned-path", {})
	stub("backend-git", {})
	stub("backend-svn", {
		revision_spec = function(root, path)
			return { command = "svn", args = { "info", "--show-item", "revision", "--", path }, cwd = root }
		end,
	})

	local old_actions, old_ya = package.loaded.actions, _G.ya
	_G.ya = {
		sync = function(fn) return fn end,
		clipboard = function(value) copied[#copied + 1] = value end,
		emit = function() end,
	}
	package.loaded.actions = nil
	local actions = require("actions")
	actions.copy_url()
	t.eq(copied[1], "https://host/svn/日本/資料.txt", "copy-url copies a readable Unicode SVN URL")

	actions.copy_url_revision()
	t.eq(copied[2], "https://host/svn/日本/資料.txt@42", "copy-url-revision preserves the decoded path and revision")
	t.deep_eq(runner_calls[1], {
		command = "svn",
		args = { "info", "--show-item", "revision", "--", "資料.txt" },
		cwd = "/wc",
	}, "copy-url-revision still queries the selected local path")
	t.eq(#notifications, 2, "successful copy actions report both clipboard operations")

	_G.ya = old_ya
	package.loaded.actions = old_actions
	for _, name in ipairs(names) do package.loaded[name] = saved_modules[name] end
end
