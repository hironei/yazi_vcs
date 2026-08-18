return function(t)
	local targets = require("core-targets")

	t.deep_eq({ targets.choose({ "a", "b" }, "hover", "cwd") }, { { "a", "b" }, "selected" }, "selected wins")
	t.deep_eq({ targets.choose({}, "hover", "cwd") }, { { "hover" }, "hovered" }, "hover wins")
	t.deep_eq({ targets.choose({}, nil, "cwd") }, { { "cwd" }, "current" }, "cwd is fallback")
	t.deep_eq(targets.relative({ "/repo", "/repo/src/a b.txt" }, "/repo"), { ".", "src/a b.txt" }, "root-relative paths")
	local _, invalid = targets.relative({ "/other/a" }, "/repo")
	t.eq(invalid, "/other/a", "paths outside root are rejected")
	t.deep_eq(targets.exclude_untracked({ "a", "b", "c" }, { a = "untracked", b = "modified" }), { "b", "c" }, "untracked paths are excluded")
	t.deep_eq(targets.exclude_ignored({ "a", "b", "c" }, { a = "ignored", b = "excluded" }), { "c" }, "ignored/excluded paths are excluded from add")
	t.eq(targets.describe({ "a", "日本語.txt" }), "  a\n  日本語.txt", "target descriptions preserve path text")
end
