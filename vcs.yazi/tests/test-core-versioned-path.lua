return function(t)
	local old_runner = package.loaded["core-runner"]
	local old_module = package.loaded["core-versioned-path"]
	local calls = {}
	package.loaded["core-runner"] = {
		run = function(spec)
			calls[#calls + 1] = spec
			if spec.command == "svn" then return { status = { success = true }, stdout = "dir\n" } end
			return { status = { success = true }, stdout = "tracked/file.txt\n" }
		end,
		error_text = function() return "command failed" end,
		summary = function(value)
			return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
		end,
	}
	package.loaded["core-versioned-path"] = nil
	local versioned = require("core-versioned-path")
	local cfg = { runner = { timeout_ms = 1000 } }

	local git = versioned.query("git", "C:/repo", "folder [x]", cfg)
	t.truthy(git, "Git tracked-path query accepts non-empty ls-files output")
	t.deep_eq(calls[1].args, { "--literal-pathspecs", "ls-files", "--cached", "--", "folder [x]" }, "Git tracked-path query uses literal pathspec arguments")

	local svn = versioned.query("svn", "C:/wc", "folder", cfg)
	t.truthy(svn, "SVN recognizes the real `svn info --show-item kind` directory value `dir`")
	t.deep_eq(calls[2].args, { "info", "--show-item", "kind", "--", "folder" }, "SVN tracked-path query preserves the path argument")

	package.loaded["core-runner"] = old_runner
	package.loaded["core-versioned-path"] = old_module
end
