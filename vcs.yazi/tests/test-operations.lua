return function(t)
	local commands = require("core-commands")
	local probe = io.popen("git --version 2>&1")
	local version = probe and probe:read("*a") or ""
	if probe then probe:close() end
	if not version:match("git version") then print("  (skipping Phase2 Git operation integration test: git not found on PATH)"); return end
	local dir = t.temp_dir()
	local function shell(args)
		local quoted = {}; for _, arg in ipairs(args) do quoted[#quoted + 1] = t.shell_quote(arg) end; return table.concat(quoted, " ")
	end
	local function git(args) return t.run_in_dir(dir, "git " .. shell(args)) end
	local function capture(args)
		local proc = t.capture_in_dir(dir, "git " .. shell(args)); local out = proc:read("*a"); proc:close(); return out
	end
	git({ "init", "-q", "-b", "main", "." }); git({ "config", "user.email", "test@example.invalid" }); git({ "config", "user.name", "test" })
	local a, b = t.path_join(dir, "space name.txt"), t.path_join(dir, "other.txt")
	local file = assert(io.open(a, "w")); file:write("base\n"); file:close(); file = assert(io.open(b, "w")); file:write("base\n"); file:close()
	git({ "add", "--", "space name.txt", "other.txt" }); git({ "commit", "-q", "-m", "init" })
	file = assert(io.open(a, "a")); file:write("a changed\n"); file:close(); file = assert(io.open(b, "a")); file:write("b staged\n"); file:close(); git({ "add", "--", "other.txt" })
	local message_dir = t.temp_dir(); local message = t.path_join(message_dir, "message.txt")
	file = assert(io.open(message, "w")); file:write("path commit\n"); file:close(); git(commands.git_commit(message, { "space name.txt" }, "paths")); os.remove(message); t.remove_tree(message_dir)
	t.eq(capture({ "log", "-1", "--format=%s" }):gsub("%s+$", ""), "path commit", "path commit commits selected file")
	t.eq(capture({ "diff", "--cached", "--name-only" }):gsub("%s+$", ""), "other.txt", "selected commit does not consume staged other file")
	git({ "reset", "-q", "HEAD", "--", "other.txt" }); t.truthy(capture(commands.git_diff({ "other.txt" })):match("b staged"), "CLI diff accepts a selected path")
	git(commands.git_discard({ "other.txt" })); t.eq(capture({ "status", "--porcelain" }):gsub("%s+$", ""), "", "discard restores the selected file")
	t.truthy(capture(commands.git_log({ "space name.txt" })):match("path commit"), "CLI log accepts a selected path")
	t.remove_tree(dir)
end
