return function(t)
	if t.is_windows then
		t.eq(t.to_file_url("C:\\tmp\\repo"), "file:///C:/tmp/repo", "Windows file URL converts single backslashes")
	else
		t.eq(t.to_file_url("/tmp/repo"), "file:///tmp/repo", "POSIX file URL remains stable")
	end
	local variables = { "GIT_EDITOR", "VISUAL", "EDITOR" }
	local before = {}
	for _, name in ipairs(variables) do before[name] = os.getenv(name) end
	local dir = t.temp_dir()
	local probe = t.path_join(dir, "editor environment.lua")
	local file = assert(io.open(probe, "w"))
	file:write('io.write(tostring(os.getenv("GIT_EDITOR")), "|", tostring(os.getenv("VISUAL")), "|", tostring(os.getenv("EDITOR")))')
	file:close()
	local polluted = t.is_windows
		and 'set "GIT_EDITOR=false" && set "VISUAL=false" && set "EDITOR=false" && '
		or 'export GIT_EDITOR=false VISUAL=false EDITOR=false; '
	local command = t.without_git_editor_env("lua " .. t.shell_quote(probe))
	local proc = assert(t.capture_in_dir(dir, "(" .. polluted .. command .. ")"))
	local output = proc:read("*a")
	local ok = proc:close()
	t.truthy(ok, "editor environment probe exits successfully")
	t.eq(output, "nil|nil|nil", "child command sees editor variables unset, not empty")
	for _, name in ipairs(variables) do
		t.eq(os.getenv(name), before[name], "child editor isolation preserves parent " .. name)
	end
	t.remove_tree(dir)
end
