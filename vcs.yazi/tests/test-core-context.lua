return function(t)
	-- `core-context.lua` calls `ya.sync(fn)` at require time (to build
	-- the capture functions), so it needs a stub to load under plain Lua.
	-- Track the boundary to catch accidental async I/O inside that callback.
	local old_ya = _G.ya
	local in_sync = false
	_G.ya = { sync = function(fn)
		return function(...)
			in_sync = true
			local result = fn(...)
			in_sync = false
			return result
		end
	end }
	local context = require("core-context")
	_G.ya = old_ya

	-- A selected directory outside the visible listing must retain its own
	-- metadata; missing metadata must be resolved after leaving ya.sync.
	do
		local old_cx, old_fs, old_Url = _G.cx, _G.fs, _G.Url
		local calls, sync_calls = 0, 0
		_G.Url = function(path) return path end
		_G.fs = { cha = function(path)
			calls = calls + 1
			if in_sync then sync_calls = sync_calls + 1 end
			return { is_dir = path == "/repo/directory" }
		end }
		local variants = {
			{ name = "File with directory metadata", entry = { url = "/repo/directory", cha = { is_dir = true } }, expected = true, lookups = 0 },
			{ name = "File with file metadata", entry = { url = "/repo/file", cha = { is_dir = false } }, expected = false, lookups = 0 },
			{ name = "File without cha", entry = { url = "/repo/directory" }, expected = true, lookups = 1 },
			{ name = "File with malformed cha", entry = { url = "/repo/directory", cha = "invalid" }, expected = true, lookups = 1 },
			{ name = "File with nonboolean is_dir", entry = { url = "/repo/directory", cha = { is_dir = "false" } }, expected = true, lookups = 1 },
			{ name = "Url with metadata", entry = { path = "/repo/directory", cha = { is_dir = true } }, expected = true, lookups = 0 },
			{ name = "Url without metadata", entry = { path = "/repo/directory" }, expected = true, lookups = 1 },
			{ name = "plain path", entry = "/repo/directory", expected = true, lookups = 1 },
			{ name = "plain file path", entry = "/repo/file", expected = false, lookups = 1 },
		}
		for _, variant in ipairs(variants) do
			local active = { selected = { variant.entry }, current = { cwd = "/repo", files = {} } }
			_G.cx = { active = active, tabs = { active, idx = 1 } }
			calls = 0
			local snapshot = context.snapshot()
			local path = context.resolve_url(variant.entry)
			t.eq(snapshot.info[path], variant.expected, variant.name .. " retains directory classification for Discard")
			t.eq(calls, variant.lookups, variant.name .. " only stats missing metadata for Discard")
			calls = 0
			local operation = context.file_operation_snapshot()
			t.eq(operation.selected[1].is_dir, variant.expected, variant.name .. " retains directory classification for Rename/Move")
			t.eq(calls, variant.lookups, variant.name .. " only stats missing metadata for Rename/Move")
		end
		t.eq(sync_calls, 0, "filesystem lookups stay outside the synchronous Yazi callback")
		local active = { selected = { "/repo/directory" }, current = {
			cwd = "/repo", files = { { url = "/repo/directory", cha = { is_dir = true } } },
			hovered = { url = "/repo/directory" },
		} }
		_G.cx = { active = active, tabs = { active, idx = 1 } }
		calls = 0
		t.truthy(context.snapshot().info["/repo/directory"], "visible directory metadata fills a plain selection")
		t.eq(calls, 0, "usable visible metadata avoids an unnecessary filesystem lookup")
		t.truthy(context.file_operation_snapshot().hovered.is_dir, "hovered items also recover absent metadata")
		active.current.files = {}
		for _, lookup in ipairs({ function() return nil end, function() error("unreadable") end }) do
			_G.fs.cha = lookup
			t.eq(context.snapshot().info["/repo/directory"], false, "unavailable metadata retains the existing non-directory fallback")
			t.eq(context.file_operation_snapshot().selected[1].is_dir, false, "file operations tolerate a failed metadata lookup")
		end
		_G.cx, _G.fs, _G.Url = old_cx, old_fs, old_Url
	end

	-- Yazi 26.8.15: `pairs(tab.selected)` yields `File`-shaped values, which
	-- carry the url under `.url`.
	t.eq(context.resolve_url({ url = "/repo/a.txt" }), "/repo/a.txt", "resolve_url unwraps a File-shaped entry")

	-- Yazi 26.5.6: `pairs(tab.selected)` yielded the `Url` itself, with no
	-- `.url` field, so it must fall through unchanged.
	t.eq(context.resolve_url("/repo/a.txt"), "/repo/a.txt", "resolve_url passes a Url-shaped entry through unchanged")

	local search_url = { path = "/repo/search.txt", spec = { is_search = true } }
	t.eq(context.resolve_url({ url = search_url }), "/repo/search.txt", "resolve_url unwraps a Search URL to its physical path")
	t.truthy(context.is_search(search_url), "is_search recognizes a Search URL")
	t.falsy(context.is_search("/repo/search.txt"), "is_search rejects a regular path")
	t.eq(context.other_tab_index(2, 1), 2, "first tab maps to the second pane")
	t.eq(context.other_tab_index(2, 2), 1, "second tab maps to the first pane")
	t.eq(context.other_tab_index(1, 1), nil, "single-tab layout has no other pane")
	t.eq(context.other_tab_index(3, 2), nil, "more than two tabs are rejected")

	do
		local snapshot = context.build_file_operation_context(
			{ { url = "/repo/selected [1].txt", cha = { is_dir = false } } },
			{ url = "/repo/hovered", cha = { is_dir = true } },
			{ path = "/repo", spec = { is_search = false } },
			{
				{ current = { cwd = "/repo/active" } },
				{ current = { cwd = "/repo/other" } },
			},
			1
		)
		t.deep_eq(snapshot.selected, { { path = "/repo/selected [1].txt", is_dir = false, search = false } }, "file operation snapshot preserves selected file metadata")
		t.deep_eq(snapshot.hovered, { path = "/repo/hovered", is_dir = true, search = false }, "file operation snapshot preserves hovered directory metadata")
		t.eq(snapshot.active_cwd, "/repo", "file operation snapshot captures active cwd")
		t.eq(snapshot.other_cwd, "/repo/other", "file operation snapshot captures paired pane cwd")
		t.eq(snapshot.other_index, 2, "file operation snapshot uses the opposite tab")
	end

	do
		local snapshot = context.build_file_operation_context(
			{ { url = "/repo/selected-dir" } },
			{ url = "/repo/selected-dir" },
			"/repo",
			{ { current = { cwd = "/repo/active" } } },
			1,
			{ { url = "/repo/selected-dir", cha = { is_dir = true } } }
		)
		t.truthy(snapshot.selected[1].is_dir, "file operation snapshot falls back to current-file metadata")
		t.truthy(snapshot.hovered.is_dir, "hovered directory uses current-file metadata when cha is absent")
	end

	do
		-- Multiple selection, File-shaped (26.8.15).
		local snapshot = context.build_snapshot(
			{ { url = "/repo/a.txt" }, { url = "/repo/b.txt" } },
			{ { url = "/repo/a.txt", cha = { is_dir = false } }, { url = "/repo/b.txt", cha = { is_dir = true } } },
			"/repo"
		)
		table.sort(snapshot.selected)
		t.deep_eq(snapshot.selected, { "/repo/a.txt", "/repo/b.txt" }, "build_snapshot lists every File-shaped selected path")
		t.eq(snapshot.info["/repo/a.txt"], false, "build_snapshot marks a selected file as not-a-directory")
		t.eq(snapshot.info["/repo/b.txt"], true, "build_snapshot reflects cha.is_dir from tab.current.files")
		t.eq(snapshot.cwd, "/repo", "build_snapshot carries cwd through unchanged")
		t.falsy(snapshot.search, "regular snapshot is not a Search View")
	end

	do
		-- Multiple selection, Url-shaped (26.5.6 compat via resolve_url).
		local snapshot = context.build_snapshot({ "/repo/a.txt", "/repo/b.txt" }, {}, "/repo")
		table.sort(snapshot.selected)
		t.deep_eq(snapshot.selected, { "/repo/a.txt", "/repo/b.txt" }, "build_snapshot lists every Url-shaped selected path")
	end

	do
		-- No selection: selected is empty, but current-file metadata is still captured.
		local snapshot = context.build_snapshot({}, { { url = "/repo/a.txt", cha = { is_dir = false } } }, "/repo")
		t.deep_eq(snapshot.selected, {}, "build_snapshot returns no selected paths when nothing is selected")
		t.eq(snapshot.info["/repo/a.txt"], false, "build_snapshot still captures current-file metadata with no selection")
	end

	do
		local snapshot = context.build_snapshot(
			{ { url = search_url } },
			{ { url = search_url, cha = { is_dir = false } } },
			"/repo",
			true
		)
		t.deep_eq(snapshot.selected, { "/repo/search.txt" }, "Search View selections are physical paths")
		t.truthy(snapshot.search, "Search View flag is preserved in the snapshot")
	end
end
