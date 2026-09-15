-- tests/test-backend-svn.lua
--
-- Every non-integration fixture below is a real `svn status --xml
-- --no-ignore --ignore-externals` capture from an SVN 1.14.5 working
-- copy (requirements §8.5), not a guessed schema — see the note at the
-- top of backend-svn.lua for exactly which states were and weren't
-- empirically reproduced.
return function(t)
	local svn = require("backend-svn")

	-- status_args
	do
		local args = svn.status_args(nil)
		local without_externals = svn.status_args(nil, false)
		t.deep_eq(without_externals, { "status", "--xml", "--no-ignore", "--", "." }, "status_args can include SVN externals")
		t.deep_eq(args, { "status", "--xml", "--no-ignore", "--ignore-externals", "--", "." }, "status_args defaults to '.'")

		local with_paths = svn.status_args({ "a.txt", "b.txt" })
		t.deep_eq(
			with_paths,
			{ "status", "--xml", "--no-ignore", "--ignore-externals", "--", "a.txt", "b.txt" },
			"status_args appends paths after --"
		)
		local without_externals = svn.status_args({ "a.txt" }, false)
		t.deep_eq(
			without_externals,
			{ "status", "--xml", "--no-ignore", "--", "a.txt" },
			"status_args omits --ignore-externals when configured"
		)
	end

	do
		local spec = svn.status_spec("C:/wc", { "a.txt" }, { ignore_externals = false })
		t.deep_eq(spec, {
			command = "svn",
			args = svn.status_args({ "a.txt" }, false),
			cwd = "C:/wc",
		}, "status_spec delegates execution to the shared runner")
		local changed, excluded = svn.parse_status_output(
			'<status><target path="a.txt"><entry path="a.txt"><wc-status item="modified" props="none"></wc-status></entry></target></status>'
		)
		t.deep_eq(changed, { ["a.txt"] = "modified" }, "parse_status_output parses runner stdout")
		t.deep_eq(excluded, {}, "parse_status_output returns the common empty excluded list")
	end

	-- modified / unversioned / ignored / deleted / property-modified
	-- (item="normal" with props="modified" on the WC root, filtered out
	-- since its path is ".").
	do
		local xml = [[<?xml version="1.0" encoding="UTF-8"?>
<status>
<target
   path=".">
<entry
   path=".">
<wc-status
   item="normal"
   revision="0"
   props="modified">
<commit
   revision="0">
<date>2026-07-29T06:57:05.762551Z</date>
</commit>
</wc-status>
</entry>
<entry
   path=".gitignore-not-used">
<wc-status
   item="unversioned"
   props="none">
</wc-status>
</entry>
<entry
   path="modified.txt">
<wc-status
   item="modified"
   revision="1"
   props="none">
<commit
   revision="1">
<author>hiron</author>
<date>2026-07-29T06:57:06.186944Z</date>
</commit>
</wc-status>
</entry>
<entry
   path="normal.txt">
<wc-status
   item="deleted"
   revision="1"
   props="none">
</wc-status>
</entry>
<entry
   path="should-be-ignored.tmp">
<wc-status
   item="ignored"
   props="none">
</wc-status>
</entry>
<entry
   path="sub\inside.txt">
<wc-status
   item="normal"
   revision="1"
   props="modified">
</wc-status>
</entry>
<entry
   path="untracked-dir">
<wc-status
   item="unversioned"
   props="none">
</wc-status>
</entry>
</target>
</status>
]]
		local changed = svn.parse_status_xml(xml)
		t.deep_eq(changed, {
			[".gitignore-not-used"] = "untracked",
			["modified.txt"] = "modified",
			["normal.txt"] = "deleted",
			["should-be-ignored.tmp"] = "ignored",
			["sub/inside.txt"] = "property_modified",
			["untracked-dir"] = "untracked",
		}, "parse_status_xml classifies a realistic mixed batch, skipping the WC-root '.' entry")
	end

	-- missing (OS-level delete, not `svn rm`)
	do
		local xml = [[<?xml version="1.0" encoding="UTF-8"?>
<status>
<target path="sub">
<entry path="sub\inside.txt">
<wc-status item="missing" revision="1" props="none">
</wc-status>
</entry>
</target>
</status>
]]
		t.deep_eq(svn.parse_status_xml(xml), { ["sub/inside.txt"] = "missing" }, "missing item maps to missing")
	end

	-- replaced (svn rm + svn add same path)
	do
		local xml = [[<?xml version="1.0" encoding="UTF-8"?>
<status>
<target path="normal.txt">
<entry path="normal.txt">
<wc-status item="replaced" revision="1" props="none">
</wc-status>
</entry>
</target>
</status>
]]
		t.deep_eq(svn.parse_status_xml(xml), { ["normal.txt"] = "replaced" }, "replaced item maps to replaced")
	end

	-- locked: a <lock> child element, NOT an attribute.
	do
		local xml = [[<?xml version="1.0" encoding="UTF-8"?>
<status>
<target path="modified.txt">
<entry path="modified.txt">
<wc-status item="normal" revision="1" props="none">
<lock>
<token>opaquelocktoken:90f44573-93f8-bb4c-b06a-f241ba5ad5f1</token>
<owner>hiron</owner>
<created>2026-07-29T06:57:46.095202Z</created>
</lock>
</wc-status>
</entry>
</target>
</status>
]]
		t.deep_eq(svn.parse_status_xml(xml), { ["modified.txt"] = "locked" }, "a <lock> child with no other change maps to locked")
	end

	-- text conflict
	do
		local xml = [[<?xml version="1.0" encoding="UTF-8"?>
<status>
<target path="modified.txt">
<entry path="modified.txt">
<wc-status item="conflicted" revision="2" props="none">
</wc-status>
</entry>
</target>
</status>
]]
		t.deep_eq(svn.parse_status_xml(xml), { ["modified.txt"] = "conflict" }, "conflicted item maps to conflict")
	end

	-- tree conflict: tree-conflicted="true" alongside item="deleted"
	-- must win over the item mapping.
	do
		local xml = [[<?xml version="1.0" encoding="UTF-8"?>
<status>
<target path="sub">
<entry path="sub\inside.txt">
<wc-status
   tree-conflicted="true"
   item="deleted"
   revision="3"
   props="none">
</wc-status>
</entry>
</target>
</status>
]]
		t.deep_eq(
			svn.parse_status_xml(xml),
			{ ["sub/inside.txt"] = "conflict" },
			"tree-conflicted='true' overrides item='deleted'"
		)
	end

	-- copied (svn copy before commit): item="added" with copied="true";
	-- copied is informational only and doesn't change the classification.
	do
		local xml = [[<?xml version="1.0" encoding="UTF-8"?>
<status>
<target path="normal-copy.txt">
<entry path="normal-copy.txt">
<wc-status
   props="none"
   copied="true"
   item="added">
</wc-status>
</entry>
</target>
</status>
]]
		t.deep_eq(svn.parse_status_xml(xml), { ["normal-copy.txt"] = "added" }, "copied='true' does not change the added classification")
	end

	-- XML entity decoding in a path attribute.
	do
		local xml =
			[[<status><target path="."><entry path="a &amp; b.txt"><wc-status item="modified" props="none"></wc-status></entry></target></status>]]
		t.deep_eq(svn.parse_status_xml(xml), { ["a & b.txt"] = "modified" }, "named entity decoded in path attribute")
	end
	do
		local xml =
			[[<status><target path="."><entry path="caf&#233;.txt"><wc-status item="modified" props="none"></wc-status></entry></target></status>]]
		t.deep_eq(svn.parse_status_xml(xml), { ["café.txt"] = "modified" }, "numeric character reference decoded in path attribute")
	end

	do
		local xml = [[<status><target path="."><entry path="external.txt"><wc-status item="external" props="modified"></wc-status></entry></target></status>]]
		t.deep_eq(
			svn.parse_status_xml(xml),
			{ ["external.txt"] = "property_modified" },
			"property modification outranks an external item"
		)
	end
	-- Optional integration test against a real `svn` binary, if one is
	-- on PATH.
	local probe = io.popen("svn --version --quiet 2>&1")
	local probe_out = probe and probe:read("*a") or ""
	if probe then
		probe:close()
	end
	if not probe_out:match("^%d+%.%d+") then
		print("  (skipping svn integration test: svn not found on PATH)")
		return
	end

	local dir = t.temp_dir()
	local repo = t.path_join(dir, "repo")
	local wc = t.path_join(dir, "wc")
	os.execute(("svnadmin create %s"):format(t.shell_quote(repo)))
	t.make_dir(wc)
	t.run_in_dir(wc, ("svn checkout -q --non-interactive %s ."):format(t.shell_quote(t.to_file_url(repo))))
	local function runwc(cmd)
		return t.run_in_dir(wc, cmd)
	end
	local function svn_command(args)
		local quoted = {}
		for _, arg in ipairs(args) do quoted[#quoted + 1] = t.shell_quote(arg) end
		return "svn " .. table.concat(quoted, " ")
	end
	local function run_svn(args)
		return t.run_in_dir(wc, svn_command(args))
	end
	local function capture_svn(args)
		local log_proc = t.capture_in_dir(wc, svn_command(args))
		local log_out = log_proc:read("*a")
		log_proc:close()
		return log_out
	end
	runwc('echo base> tracked.txt')
	runwc("svn add -q tracked.txt")
	runwc("svn commit -q --non-interactive -m init")

	-- Exercise native working-copy moves with actual literal argv. SVN records
	-- these as local add-with-history changes; nothing here changes repository URLs.
	local function write_file(path, content)
		local file, err = io.open(path, "wb")
		assert(file, err)
		file:write(content)
		file:close()
	end
	local rename_source = t.path_join(wc, "rename source")
	local rename_directory_source = t.path_join(wc, "rename directory")
	local directory_source = t.path_join(wc, "directory with spaces")
	local destination_dir = t.path_join(wc, "destination")
	t.make_dir(rename_source)
	t.make_dir(rename_directory_source)
	t.make_dir(directory_source)
	t.make_dir(destination_dir)
	write_file(t.path_join(rename_source, "old [ab].txt"), "rename")
	write_file(t.path_join(rename_directory_source, "inside.txt"), "directory rename")
	write_file(t.path_join(rename_source, "literal@123.txt"), "peg")
	write_file(t.path_join(rename_source, "ending@"), "ending at sign")
	write_file(t.path_join(wc, "-dash [ab].txt"), "dash")
	write_file(t.path_join(wc, "space name.txt"), "space")
	write_file(t.path_join(directory_source, "inside.txt"), "directory")
	local delete_file = t.path_join(wc, "delete file.txt")
	local delete_directory = t.path_join(wc, "delete directory")
	t.make_dir(delete_directory)
	write_file(delete_file, "delete me")
	write_file(t.path_join(delete_directory, "inside.txt"), "delete directory")
	local commands = require("core-commands")
	local add_status = run_svn(commands.svn_add({ "rename source", "rename directory", "-dash [ab].txt", "space name.txt", "directory with spaces", "destination", "delete file.txt", "delete directory" }))
	t.truthy(add_status, "[integration] svn add prepares file-move fixtures")
	local fixture_commit = runwc('svn commit --non-interactive -m "move fixtures"')
	t.truthy(fixture_commit, "[integration] SVN move fixtures commit successfully")
	local function exists(path)
		local file = io.open(path, "rb")
		if not file then return false end
		file:close()
		return true
	end
	local delete_status = run_svn(commands.svn_delete({ "delete file.txt", "delete directory" }))
	t.truthy(delete_status, "[integration] svn delete schedules file and directory deletion")
	t.falsy(exists(t.path_join(wc, "delete file.txt")), "[integration] svn delete removes a tracked file from the working copy")
	t.falsy(exists(t.path_join(wc, "delete directory")), "[integration] svn delete removes a tracked directory from the working copy")
	local delete_changes = svn.parse_status_xml(capture_svn(svn.status_args({ "delete file.txt", "delete directory" })))
	t.eq(delete_changes["delete file.txt"], "deleted", "[integration] svn delete reports the file as scheduled deleted")
	t.eq(delete_changes["delete directory"], "deleted", "[integration] svn delete reports the directory as scheduled deleted")
	local rename_status = run_svn(commands.svn_move({ "rename source/old [ab].txt" }, "rename source/new name [x].txt"))
	t.truthy(rename_status, "[integration] svn move accepts -- and a spaced rename destination")
	t.truthy(exists(t.path_join(rename_source, "new name [x].txt")), "[integration] svn move renames a tracked file in the working copy")
	t.falsy(exists(t.path_join(rename_source, "old [ab].txt")), "[integration] svn move removes the old local path")
	local directory_rename = run_svn(commands.svn_move({ "rename directory" }, "renamed directory"))
	t.truthy(directory_rename, "[integration] svn move renames a versioned directory")
	t.truthy(exists(t.path_join(t.path_join(wc, "renamed directory"), "inside.txt")), "[integration] svn move preserves a directory's contents on rename")
	t.falsy(exists(rename_directory_source), "[integration] svn move removes the old directory name")
	local peg_rename = run_svn(commands.svn_move({ "rename source/literal@123.txt" }, "rename source/literal@456.txt"))
	t.truthy(peg_rename, "[integration] svn move escapes a filename that resembles a peg revision")
	t.truthy(exists(t.path_join(rename_source, "literal@456.txt")), "[integration] peg-like SVN filename is renamed literally")
	local ending_peg_rename = run_svn(commands.svn_move({ "rename source/ending@" }, "rename source/ending@renamed@"))
	t.truthy(ending_peg_rename, "[integration] svn move escapes a source ending in @ without changing the exact destination")
	t.truthy(exists(t.path_join(rename_source, "ending@renamed@")), "[integration] destination ending in @ is kept exact")
	local move_status = run_svn(commands.svn_move(
		{ "-dash [ab].txt", "space name.txt", "directory with spaces" },
		"destination"
	))
	t.truthy(move_status, "[integration] svn move accepts several sources and an existing destination directory")
	t.truthy(exists(t.path_join(destination_dir, "-dash [ab].txt")), "[integration] svn move handles a leading-dash basename")
	t.truthy(exists(t.path_join(destination_dir, "space name.txt")), "[integration] svn move handles a spaced filename")
	t.truthy(exists(t.path_join(t.path_join(destination_dir, "directory with spaces"), "inside.txt")), "[integration] svn move transfers a versioned directory")
	local move_changes = svn.parse_status_xml(capture_svn(svn.status_args({
		"rename source/old [ab].txt", "destination/-dash [ab].txt", "destination/space name.txt", "destination/directory with spaces/inside.txt",
	})))
	t.eq(move_changes["rename source/old [ab].txt"], "deleted", "[integration] svn move schedules the old source for deletion")
	t.eq(move_changes["destination/-dash [ab].txt"], "added", "[integration] svn move schedules history-aware destination additions")

	runwc('echo changed>> tracked.txt')
	runwc('echo x> new.txt')

	local proc = t.capture_in_dir(wc, "svn status --xml --no-ignore --ignore-externals -- tracked.txt new.txt")
	local out = proc:read("*a")
	proc:close()

	local changed = svn.parse_status_xml(out)
	t.eq(changed["tracked.txt"], "modified", "[integration] real svn: modified file detected")
	t.eq(changed["new.txt"], "untracked", "[integration] real svn: unversioned file detected")

	local log_preview = require("core-log-preview")
	for index = 1, 6 do
		runwc(("echo revision %d %s>> tracked.txt"):format(index, string.rep("x", index)))
		runwc(("svn commit -q --non-interactive -m \"preview %d\""):format(index))
	end
	local preview_entries = log_preview.parse_svn(capture_svn(log_preview.svn_args("tracked.txt")))
	t.eq(#preview_entries, 5, "[integration] real svn log preview returns only the five newest entries")
	t.truthy(preview_entries[1].message:match("preview 6"), "[integration] real svn log preview keeps newest-first order")

	t.remove_tree(dir)
end
