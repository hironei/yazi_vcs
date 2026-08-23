return function(t)
	-- `core-context.lua` calls `ya.sync(fn)` at require time (to build
	-- `M.snapshot`), so it needs a passthrough stub just to load under plain
	-- Lua. `resolve_url` and `build_snapshot` themselves make no Yazi API
	-- calls and are exercised directly below.
	local old_ya = _G.ya
	_G.ya = { sync = function(fn) return fn end }
	local context = require("core-context")
	_G.ya = old_ya

	-- Yazi 26.8.15: `pairs(tab.selected)` yields `File`-shaped values, which
	-- carry the url under `.url`.
	t.eq(context.resolve_url({ url = "/repo/a.txt" }), "/repo/a.txt", "resolve_url unwraps a File-shaped entry")

	-- Yazi 26.5.6: `pairs(tab.selected)` yielded the `Url` itself, with no
	-- `.url` field, so it must fall through unchanged.
	t.eq(context.resolve_url("/repo/a.txt"), "/repo/a.txt", "resolve_url passes a Url-shaped entry through unchanged")

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
end
