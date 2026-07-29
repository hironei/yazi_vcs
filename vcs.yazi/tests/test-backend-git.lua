-- tests/test-backend-git.lua
return function(t)
	local git = require("backend-git")

	-- status_args
	do
		local args = git.status_args(nil)
		t.deep_eq(args, {
			"--no-optional-locks",
			"-c",
			"core.quotePath=",
			"status",
			"--porcelain=v2",
			"-z",
			"--untracked-files=all",
			"--ignored=matching",
		}, "status_args with no paths omits the -- separator")

		local with_paths = git.status_args({ "a.txt", "b.txt" })
		t.eq(with_paths[#with_paths - 2], "--", "status_args appends -- before paths")
		t.eq(with_paths[#with_paths - 1], "a.txt", "status_args includes the first path")
		t.eq(with_paths[#with_paths], "b.txt", "status_args includes the second path")
	end

	-- Ordinary changed entries + untracked + ignored, from a real
	-- `git --no-optional-locks -c core.quotePath= status --porcelain=v2
	-- -z --untracked-files=all --ignored=matching` capture.
	do
		local blob = table.concat({
			"1 .M N... 100644 100644 100644 45b983be36b73c0788dc9cbcb76cbb80fc7bb057 45b983be36b73c0788dc9cbcb76cbb80fc7bb057 tracked.txt",
			"? new.txt",
			"! a.log",
		}, "\0") .. "\0"
		local changed, excluded = git.parse_status(blob)
		t.deep_eq(changed, {
			["tracked.txt"] = "modified",
			["new.txt"] = "untracked",
			["a.log"] = "ignored",
		}, "parse_status classifies ordinary-modified, untracked, and ignored-file entries")
		t.deep_eq(excluded, {}, "an ignored *file* (no trailing slash) is not treated as an excluded directory")
	end

	-- Rename record (type "2") consumes an extra NUL field for the
	-- original path — the critical regression case from requirements
	-- §8.4.1. A follow-up ordinary record must parse correctly too,
	-- proving the parser resynced to the right field boundary.
	do
		local blob = table.concat({
			"2 R. N... 100644 100644 100644 45b983be36b73c0788dc9cbcb76cbb80fc7bb057 45b983be36b73c0788dc9cbcb76cbb80fc7bb057 R100 new.txt",
			"old.txt",
			"1 .M N... 100644 100644 100644 45b983be36b73c0788dc9cbcb76cbb80fc7bb057 45b983be36b73c0788dc9cbcb76cbb80fc7bb057 after.txt",
		}, "\0") .. "\0"
		local changed = git.parse_status(blob)
		t.deep_eq(changed, {
			["new.txt"] = "replaced",
			["after.txt"] = "modified",
		}, "rename record's orig-path field is consumed, not misparsed as its own entry")
	end

	-- Unmerged/conflict record (type "u"), from a real merge conflict.
	do
		local blob = "u UU N... 100644 100644 100644 100644 "
			.. "df967b96a579e45a18b8251732d16804b2e56a55 "
			.. "e8a99e0734724ff0c1fbedf23cb1f85dc5c31189 "
			.. "ad85ceb47e302b638617225f92531f63ff9647e4 f.txt\0"
		local changed = git.parse_status(blob)
		t.deep_eq(changed, { ["f.txt"] = "conflict" }, "unmerged record maps to conflict")
	end

	-- A wholly-ignored directory is reported once, with a trailing
	-- slash, and goes into `excluded` rather than `changed`.
	do
		local blob = "! node_modules/\0"
		local changed, excluded = git.parse_status(blob)
		t.deep_eq(changed, {}, "an ignored directory produces no changed entry")
		t.deep_eq(excluded, { "node_modules" }, "an ignored directory's trailing slash is stripped into excluded")
	end

	-- classify_xy coverage via synthetic "1" records (not all of these
	-- combinations occur in practice under default status flags, but
	-- the classifier should still handle them sensibly).
	do
		local function xy(pair)
			return ("1 %s N... 100644 100644 100644 h h p.txt\0"):format(pair)
		end
		t.eq(select(1, git.parse_status(xy("A.")))["p.txt"], "added", "XY 'A.' -> added")
		t.eq(select(1, git.parse_status(xy(".M")))["p.txt"], "modified", "XY '.M' -> modified")
		t.eq(select(1, git.parse_status(xy("M.")))["p.txt"], "modified", "XY 'M.' -> modified")
		t.eq(select(1, git.parse_status(xy(".D")))["p.txt"], "deleted", "XY '.D' -> deleted")
		t.eq(select(1, git.parse_status(xy("D.")))["p.txt"], "deleted", "XY 'D.' -> deleted")
		t.eq(select(1, git.parse_status(xy("R.")))["p.txt"], "replaced", "XY 'R.' -> replaced")
	end

	-- Optional integration test against a real `git` binary, if one is
	-- on PATH. Builds a throwaway repo covering modified/untracked/
	-- ignored/renamed and checks the parser end to end against genuine
	-- output, not just hand-built fixtures.
	local probe = io.popen("git --version 2>&1")
	local probe_out = probe and probe:read("*a") or ""
	if probe then
		probe:close()
	end
	if not probe_out:match("git version") then
		print("  (skipping git integration test: git not found on PATH)")
		return
	end

	local dir = t.temp_dir()
	local function run(cmd)
		t.run_in_dir(dir, cmd)
	end
	run("git init -q -b main .")
	run("git config user.email t@t.com")
	run("git config user.name t")
	run("echo base> tracked.txt")
	run("echo *.log> .gitignore")
	run("git add tracked.txt .gitignore")
	run("git commit -q -m init")
	run("echo changed>> tracked.txt")
	run("echo x> new.txt")
	run(t.is_windows and "type nul > a.log" or ": > a.log")
	run("git mv tracked.txt renamed.txt")

	local proc = t.capture_in_dir(
		dir,
		"git --no-optional-locks -c core.quotePath= status --porcelain=v2 -z --untracked-files=all --ignored=matching"
	)
	local out = proc:read("*a")
	proc:close()

	local changed, excluded = git.parse_status(out)
	t.eq(changed["renamed.txt"], "replaced", "[integration] real git: rename shows up as replaced")
	t.eq(changed["new.txt"], "untracked", "[integration] real git: untracked file detected")
	t.deep_eq(excluded, {}, "[integration] real git: a.log is an ignored *file*, not a directory")

	t.remove_tree(dir)
end
