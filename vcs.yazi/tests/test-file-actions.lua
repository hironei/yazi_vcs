return function(t)
	local saved_modules = {}
	local function stub(name, value)
		saved_modules[name] = package.loaded[name]
		package.loaded[name] = value
	end

	local cfg = { runner = { timeout_ms = 1000 }, detection = { priority = { "git", "svn" } } }
	local old_actions = package.loaded["file-actions"]
	local context
	local notifications, emitted, cleared, runner_calls = {}, {}, {}, {}
	local input_value, input_event = "new name.txt", 1
	local runner_side_effect
	local runner_throw
	local runner_output = { status = { success = true, code = 0 }, stdout = "", stderr = "" }
	local filesystem = {}
	local locked = false
	local lock_ends = 0
	local Context = { file_operation_snapshot = function() return context end }
	local Detector = {
		detect = function(path)
			if tostring(path):sub(1, 9) == "/outside/" then return nil, nil end
			if tostring(path):sub(1, 5) == "/svn/" then return "svn", "/svn" end
			if tostring(path):sub(1, 7) == "/other/" then return "git", "/other" end
			return "git", "/repo"
		end,
	}
	local Notify = {}
	for _, method in ipairs({ "info", "warn", "error" }) do
		Notify[method] = function(...)
			local values = { ... }
			local format = table.remove(values, 1)
			notifications[#notifications + 1] = { method = method, message = string.format(format, table.unpack(values)) }
		end
	end
	local State = {
		begin_action = function()
			if locked then return false end
			locked = true
			return true
		end,
		end_action = function() locked = false; lock_ends = lock_ends + 1 end,
		clear_root = function(root) cleared[#cleared + 1] = root end,
	}
	local Runner = {
		run = function(spec)
			runner_calls[#runner_calls + 1] = spec
			if runner_throw then error(runner_throw) end
			if runner_side_effect then runner_side_effect(spec) end
			return runner_output, nil
		end,
		error_text = function(output, err)
			if not output then return tostring(err or "unknown error") end
			return output.stderr ~= "" and output.stderr or ("exit code " .. output.status.code)
		end,
		summary = function(message, limit) return tostring(message):sub(1, limit) end,
	}
	local Config = { get = function() return cfg end }
	stub("config", Config)
	stub("core-context", Context)
	stub("core-detector", Detector)
	stub("core-notify", Notify)
	stub("core-runner", Runner)
	stub("core-scope", {})
	stub("core-state", State)
	stub("core-temp", {})
	package.loaded["file-actions"] = nil
	local actions = require("file-actions")

	local old_ya, old_fs, old_Url, old_last_input = _G.ya, _G.fs, _G.Url, _G.last_input
	_G.ya = {
		input = function(options)
			_G.last_input = options
			return input_value, input_event
		end,
		emit = function(event, args) emitted[#emitted + 1] = { event = event, args = args } end,
	}
	_G.Url = function(path) return path end
	_G.fs = { cha = function(path) return filesystem[tostring(path):gsub("\\", "/")] end }

	local function reset()
		notifications, emitted, cleared, runner_calls = {}, {}, {}, {}
		filesystem = {}
		locked, lock_ends = false, 0
		runner_side_effect = nil
		runner_throw = nil
		runner_output = { status = { success = true, code = 0 }, stdout = "", stderr = "" }
		input_value, input_event = "new name.txt", 1
	end
	local function source(path, is_dir)
		return { path = path, is_dir = is_dir == true, search = false }
	end
	local function operation_context(selected, hovered, other_cwd)
		return {
			selected = selected or {}, hovered = hovered, active_cwd = "/repo/src", active_search = false,
			tab_count = other_cwd and 2 or 1, other_cwd = other_cwd, other_search = false,
		}
	end
	local function add_source_files(sources)
		for _, item in ipairs(sources) do filesystem[item.path] = { is_dir = item.is_dir } end
	end
	local function assert_refreshed(label, root)
		t.eq(#emitted, 1, label .. " emits a file refresh")
		t.eq(emitted[1] and emitted[1].event, "refresh", label .. " refreshes the file listing")
		t.deep_eq(cleared, { root or "/repo" }, label .. " invalidates cached repository status")
		t.falsy(locked, label .. " releases the repository operation lock")
	end

	reset()
	local rename_source = source("/repo/src/old [ab].txt", false)
	context = operation_context({ rename_source }, source("/repo/src/hovered.txt", false))
	filesystem["/repo/src"] = { is_dir = true }
	add_source_files({ rename_source })
	actions.rename()
	t.eq(_G.last_input.value, "old [ab].txt", "rename prompt starts with the current basename")
	t.deep_eq(runner_calls[1], {
		command = "git", cwd = "/repo",
		args = { "--literal-pathspecs", "mv", "--", "src/old [ab].txt", "src/new name.txt" },
	}, "rename runs git mv with literal root-relative argv")
	assert_refreshed("successful rename")

	reset()
	local svn_rename_source = source("/svn/source/old [ab].txt", false)
	context = operation_context({ svn_rename_source })
	context.active_cwd = "/svn/source"
	filesystem["/svn/source"] = { is_dir = true }
	add_source_files({ svn_rename_source })
	actions.rename()
	t.deep_eq(runner_calls[1], {
		command = "svn", cwd = "/svn",
		args = { "move", "--", "source/old [ab].txt", "source/new name.txt" },
	}, "SVN rename uses svn move with a working-copy-relative destination")
	assert_refreshed("successful SVN rename", "/svn")

	reset()
	context = operation_context({ rename_source })
	filesystem["/repo/src"] = { is_dir = true }
	add_source_files({ rename_source })
	input_event = 0
	actions.rename()
	t.eq(#runner_calls, 0, "cancelled rename does not invoke Git")
	t.eq(#emitted, 0, "cancelled rename does not refresh or mutate state")
	t.falsy(locked, "cancelled rename releases the lock")
	t.eq(lock_ends, 1, "cancelled rename closes the operation lock")

	reset()
	context = operation_context({ rename_source })
	filesystem["/repo/src"] = { is_dir = true }
	add_source_files({ rename_source })
	input_value = ""
	actions.rename()
	t.eq(#runner_calls, 0, "empty rename input is treated as cancellation")
	t.eq(#emitted, 0, "empty rename input leaves the listing unchanged")
	t.falsy(locked, "empty rename input releases the lock")

	reset()
	local first = source("/repo/src/a.txt", false)
	local second = source("/repo/src/-b [cd].txt", false)
	context = operation_context({ second, first }, source("/repo/src/hovered.txt", false), "/repo/destination")
	filesystem["/repo/src"] = { is_dir = true }
	filesystem["/repo/destination"] = { is_dir = true }
	add_source_files({ first, second })
	actions.move_other_pane()
	t.deep_eq(runner_calls[1], {
		command = "git", cwd = "/repo",
		args = { "--literal-pathspecs", "mv", "--", "src/-b [cd].txt", "src/a.txt", "destination" },
	}, "other-pane move uses selected sources in stable order and preserves names")
	assert_refreshed("successful other-pane move")

	reset()
	local svn_first = source("/svn/source/-a [ab].txt", false)
	local svn_second = source("/svn/source/日本語.txt", false)
	context = operation_context({ svn_first, svn_second }, nil, "/svn/destination")
	context.active_cwd = "/svn/source"
	filesystem["/svn/source"] = { is_dir = true }
	filesystem["/svn/destination"] = { is_dir = true }
	add_source_files({ svn_first, svn_second })
	actions.move_other_pane()
	t.deep_eq(runner_calls[1], {
		command = "svn", cwd = "/svn",
		args = { "move", "--", "source/-a [ab].txt", "source/日本語.txt", "destination" },
	}, "SVN split-tabs move uses one same-working-copy move command")
	assert_refreshed("successful SVN other-pane move", "/svn")

	reset()
	context = operation_context({ first }, nil, "/repo/destination")
	filesystem["/repo/src"] = { is_dir = true }
	filesystem["/repo/destination"] = { is_dir = true }
	filesystem["/repo/destination/a.txt"] = { is_dir = false }
	add_source_files({ first })
	actions.move_other_pane()
	t.eq(#runner_calls, 0, "existing other-pane target blocks Git invocation")
	t.eq(#emitted, 0, "preflight rejection does not refresh")
	t.falsy(locked, "preflight rejection releases the lock")

	reset()
	context = operation_context({ first }, nil, "/other/destination")
	filesystem["/repo/src"] = { is_dir = true }
	filesystem["/other/destination"] = { is_dir = true }
	add_source_files({ first })
	actions.move_other_pane()
	t.eq(#runner_calls, 0, "other pane in another Git working tree is rejected")
	t.eq(#emitted, 0, "different-root rejection does not refresh")
	t.truthy(notifications[#notifications].message:match("same VCS working copy"), "different-root rejection explains the repository boundary")

	reset()
	context = operation_context({ first }, nil, "/svn/destination")
	filesystem["/repo/src"] = { is_dir = true }
	filesystem["/svn/destination"] = { is_dir = true }
	add_source_files({ first })
	actions.move_other_pane()
	t.eq(#runner_calls, 0, "a destination inside a different VCS working copy is rejected")
	t.truthy(notifications[#notifications].message:match("same VCS working copy"), "mixed-backend rejection explains the working-copy boundary")

	reset()
	context = operation_context({ first }, nil, nil)
	actions.move_other_pane()
	t.eq(#runner_calls, 0, "single-tab layout is rejected")
	t.truthy(notifications[#notifications].message:match("two%-tab split%-tabs"), "single-tab layout reports the split-tabs requirement")

	reset()
	context = operation_context({ first }, nil, "/repo/destination")
	filesystem["/repo/src"] = { is_dir = true }
	filesystem["/repo/destination"] = { is_dir = true }
	add_source_files({ first })
	runner_output = { status = { success = false, code = 1 }, stdout = "", stderr = "simulated git mv failure" }
	runner_side_effect = function()
		filesystem["/repo/src/a.txt"] = nil
		filesystem["/repo/destination/a.txt"] = { is_dir = false }
	end
	actions.move_other_pane()
	t.eq(#runner_calls, 1, "failed move reaches Git")
	t.truthy(filesystem["/repo/destination/a.txt"], "simulated batch move leaves its partial result in place")
	assert_refreshed("failed other-pane move")
	t.eq(notifications[#notifications].message, "Git move failed: simulated git mv failure", "failed move reports the Git error")

	reset()
	local svn_failure_source = source("/svn/source/a.txt", false)
	context = operation_context({ svn_failure_source }, nil, "/svn/destination")
	context.active_cwd = "/svn/source"
	filesystem["/svn/source"] = { is_dir = true }
	filesystem["/svn/destination"] = { is_dir = true }
	add_source_files({ svn_failure_source })
	runner_output = { status = { success = false, code = 1 }, stdout = "", stderr = "simulated svn move failure" }
	actions.move_other_pane()
	t.eq(runner_calls[1].command, "svn", "failed SVN move invokes SVN")
	assert_refreshed("failed SVN other-pane move", "/svn")
	t.eq(notifications[#notifications].message, "SVN move failed: simulated svn move failure", "failed move reports the SVN error")

	reset()
	local long_outside_source = source("/outside/" .. string.rep("a", 300) .. ".txt", false)
	context = operation_context({ long_outside_source })
	actions.rename()
	t.truthy(#notifications[#notifications].message < 180, "path-bearing errors remain bounded for long names")

	reset()
	context = operation_context({ first }, nil, "/repo/destination")
	filesystem["/repo/src"] = { is_dir = true }
	filesystem["/repo/destination"] = { is_dir = true }
	add_source_files({ first })
	runner_throw = "simulated command runner exception"
	actions.move_other_pane()
	assert_refreshed("move after runner exception")
	t.eq(notifications[#notifications].message, "Git move failed: simulated command runner exception", "runner exception becomes a bounded operation error")

	_G.ya, _G.fs, _G.Url, _G.last_input = old_ya, old_fs, old_Url, old_last_input
	for name, value in pairs(saved_modules) do package.loaded[name] = value end
	package.loaded["file-actions"] = old_actions
end
