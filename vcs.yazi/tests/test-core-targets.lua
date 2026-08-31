return function(t)
	local targets = require("core-targets")

	t.deep_eq({ targets.choose({ "a", "b" }, "cwd") }, { { "a", "b" }, "selected", true }, "selected wins")
	t.deep_eq({ targets.choose({}, "cwd") }, { { "cwd" }, "cwd", false }, "cwd is fallback")
	t.deep_eq({ targets.choose({}, nil) }, { {}, nil, false }, "empty context has no target")
	local no_search_target, no_search_reason = targets.resolve({}, "/repo", {}, function() return "git", "/repo" end, { search = true })
	t.falsy(no_search_target, "Search View does not fall back to cwd without a selection")
	t.eq(no_search_reason.code, "no-target", "Search View empty selection is classified")
	t.eq(require("core-path").parent("/repo/src/a.txt"), "/repo/src", "file detection starts at parent")
	t.eq(require("core-path").parent("C:/repo/a.txt"), "C:/repo", "Windows file detection starts at parent")
	t.truthy(require("core-path").same("C:/Repo", "c:/repo"), "Windows repository roots compare case-insensitively")
	t.falsy(require("core-path").same("/Repo", "/repo"), "POSIX repository roots remain case-sensitive")

	local function detect(repositories)
		return function(path)
			for _, item in ipairs(repositories) do
				if path == item.path or path:sub(1, #item.path + 1) == item.path .. "/" then return item.kind, item.root end
			end
			return nil, nil
		end
	end
	local same = targets.resolve({ "/repo/a.txt", "/repo/src" }, "/repo", { ["/repo/a.txt"] = false, ["/repo/src"] = true }, detect({
		{ path = "/repo", kind = "git", root = "/repo" },
	}))
	t.eq(same.source, "selected", "selected scope is explicit")
	t.truthy(same.explicit, "selected scope keeps explicit flag")
	t.falsy(same.repository, "ordinary selected paths are path-scoped")
	local cwd = targets.resolve({}, "/repo", {}, detect({ { path = "/repo", kind = "git", root = "/repo" } }))
	t.eq(cwd.source, "cwd", "cwd scope is distinguishable")
	t.falsy(cwd.explicit, "cwd scope is not explicit")
	t.truthy(cwd.repository, "repository root is repository-scoped")
	local selected_root = targets.resolve({ "/repo" }, "/work", { ["/repo"] = true }, detect({ { path = "/repo", kind = "git", root = "/repo" } }))
	t.truthy(selected_root.repository, "selected repository root is repository-scoped")
	local search_scope = targets.resolve({ "/repo/a.txt" }, "/repo", { ["/repo/a.txt"] = false }, detect({
		{ path = "/repo", kind = "git", root = "/repo" },
	}), { search = true })
	t.truthy(search_scope.search, "selected Search View scope is marked explicitly")
	t.truthy(search_scope.explicit, "selected Search View scope remains explicit")
	local ignored_hover = targets.resolve({}, "/work", {}, detect({ { path = "/work", kind = "git", root = "/work" } }))
	t.eq(ignored_hover.paths[1], ".", "hovered paths are not part of resolution")
	local mixed, reason = targets.resolve({ "/repo-a", "/repo-b" }, "/work", { ["/repo-a"] = true, ["/repo-b"] = true }, detect({
		{ path = "/repo-a", kind = "git", root = "/repo-a" },
		{ path = "/repo-b", kind = "git", root = "/repo-b" },
	}))
	t.falsy(mixed, "different repositories are rejected")
	t.eq(reason.code, "mixed", "mixed repository rejection is classified")
	local mixed_vcs, mixed_vcs_reason = targets.resolve({ "/repo", "/outside" }, "/work", { ["/repo"] = true, ["/outside"] = false }, detect({
		{ path = "/repo", kind = "git", root = "/repo" },
	}))
	t.falsy(mixed_vcs, "VCS and non-VCS selections are rejected")
	t.eq(mixed_vcs_reason.code, "mixed", "VCS and non-VCS rejection is classified")
	local outside, outside_reason = targets.resolve({ "/outside-a", "/outside-b" }, "/work", { ["/outside-a"] = false, ["/outside-b"] = false }, detect({}))
	t.falsy(outside, "multiple non-VCS selections are rejected")
	t.eq(outside_reason.code, "not-found", "multiple non-VCS selections are not classified as mixed")
	local outside_first, outside_first_reason = targets.resolve({ "/outside", "/repo" }, "/work", { ["/outside"] = false, ["/repo"] = true }, detect({
		{ path = "/repo", kind = "git", root = "/repo" },
	}))
	t.falsy(outside_first, "non-VCS followed by VCS selection is rejected")
	t.eq(outside_first_reason.code, "mixed", "non-VCS and VCS selection is classified as mixed regardless of order")
	local case_scope = targets.resolve({ "C:/repo/File.txt" }, "C:/work", { ["C:/repo/File.txt"] = false }, function(path)
		if path:lower() == "c:/repo" then return "git", "C:/Repo" end
		return nil, nil
	end)
	t.deep_eq(case_scope.paths, { "File.txt" }, "Windows case differences do not break root-relative resolution")
	t.deep_eq(targets.relative({ "/repo", "/repo/src/a b.txt" }, "/repo"), { ".", "src/a b.txt" }, "root-relative paths")
	local _, invalid = targets.relative({ "/other/a" }, "/repo")
	t.eq(invalid, "/other/a", "paths outside root are rejected")
	t.deep_eq(targets.exclude_untracked({ "a", "b", "c" }, { a = "untracked", b = "modified" }), { "b", "c" }, "untracked paths are excluded")
	t.deep_eq(targets.exclude_ignored({ "a", "b", "c" }, { a = "ignored", b = "excluded" }), { "c" }, "ignored/excluded paths are excluded from add")
	t.eq(targets.describe({ "a", "日本語.txt" }), "  a\n  日本語.txt", "target descriptions preserve path text")
end
