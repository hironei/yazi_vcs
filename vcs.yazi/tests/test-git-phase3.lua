return function(t)
	local git = require("core-git")
	local probe = io.popen("git --version 2>&1")
	local version = probe and probe:read("*a") or ""
	if probe then probe:close() end
	if not version:match("git version") then
		print("  (skipping Phase3 Git integration test: git not found on PATH)")
		return
	end

	local dir, bare = t.temp_dir(), t.temp_dir()
	local function shell(args)
		local quoted = {}
		for _, arg in ipairs(args) do quoted[#quoted + 1] = t.shell_quote(arg) end
		return table.concat(quoted, " ")
	end
	local function run(args)
		return t.run_in_dir(dir, "git " .. shell(args))
	end
	local function capture(args)
		local proc = t.capture_in_dir(dir, "git " .. shell(args))
		local out = proc:read("*a")
		proc:close()
		return out
	end

	t.run_in_dir(bare, "git init --bare -q")
	run({ "init", "-q", "-b", "main", "." })
	run({ "config", "user.email", "test@example.invalid" })
	run({ "config", "user.name", "test" })
	local file = assert(io.open(t.path_join(dir, "base.txt"), "w"))
	file:write("base\n")
	file:close()
	run({ "add", "--", "base.txt" })
	run({ "commit", "-q", "-m", "init" })
	run({ "remote", "add", "origin", bare })

	local push = git.push_args("origin", "main", true)
	run(push)
	t.truthy(capture({ "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}" }):match("origin/main"), "upstream is configured after push")
	t.deep_eq(git.push_args(nil, nil, false), { "push" }, "upstream push has no force/all/tags flags")

	run(git.create_branch_args("feature/one", "main", false))
	run(git.switch_branch_args("feature/one"))
	local branches = git.parse_branches(capture(git.branch_list_args(true)))
	t.truthy(git.find_branch(branches, "feature/one"), "created local branch is listed")
	run(git.rename_branch_args(nil, "feature/renamed"))
	t.truthy(git.find_branch(git.parse_branches(capture(git.branch_list_args(false))), "feature/renamed"), "renamed branch is listed")
	run(git.switch_branch_args("main"))
	run({ "branch", "-d", "feature/renamed" })
	t.falsy(git.find_branch(git.parse_branches(capture(git.branch_list_args(false))), "feature/renamed"), "safe delete removes merged branch")

	run({ "switch", "-c", "remote-feature" })
	run({ "push", "--set-upstream", "origin", "remote-feature" })
	run({ "switch", "main" })
	run({ "branch", "-D", "remote-feature" })
	local remote_branches = git.parse_branches(capture(git.branch_list_args(true)))
	t.truthy(git.find_branch(remote_branches, "origin/remote-feature"), "remote tracking branch is listed")
	run(git.switch_branch_args("origin/remote-feature", "origin/remote-feature", nil))
	t.eq(capture({ "branch", "--show-current" }):gsub("%s+$", ""), "remote-feature", "remote branch is tracked into a local branch")

	run({ "checkout", "--detach", "-q" })
	t.eq(capture(git.current_branch_args()):gsub("%s+$", ""), "", "detached HEAD has no current branch")
	t.remove_tree(dir)
	t.remove_tree(bare)
end
