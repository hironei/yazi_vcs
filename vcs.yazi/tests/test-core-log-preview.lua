return function(t)
	local log = require("core-log-preview")

	t.eq(log.LIMIT, 5, "log preview has a fixed five-entry limit")
	t.eq(log.message(nil, "outside-repository"), "No Git or SVN repository.", "VCS-outside message is explanatory")
	t.eq(log.message(nil, "untracked"), "Untracked files have no history.", "untracked message is explanatory")
	t.eq(log.message(nil, "empty"), "No history for the hovered item.", "empty-history message is explanatory")
	t.eq(log.message("svn", "command-failed", "exit code 1"), "SVN log failed: exit code 1", "command failure message includes the backend")
	t.deep_eq(
		log.git_args("dir/a b.txt"),
		{ "--no-pager", "log", "-n", "5", "--format=%h%x09%s", "--", "dir/a b.txt" },
		"Git log keeps the relative path as one argument"
	)
	t.deep_eq(log.svn_args("日本語/-dash.txt"), { "log", "--xml", "-l", "5", "--", "日本語/-dash.txt" }, "SVN log keeps path boundaries")
	t.deep_eq(log.git_args(""), { "--no-pager", "log", "-n", "5", "--format=%h%x09%s", "--", "." }, "root Git log uses dot")
	t.deep_eq(log.svn_args(""), { "log", "--xml", "-l", "5", "--", "." }, "root SVN log uses dot")

	local git_output = table.concat({
		"a1b2c3d\tfirst subject",
		"b2c3d4e\tsecond subject with spaces",
		"c3d4e5f\tthird subject",
		"d4e5f6a\tfourth subject",
		"e5f6a7b\tfifth subject",
		"f6a7b8c\tsixth subject must be ignored",
	}, "\n")
	t.deep_eq(
		log.parse_git(git_output),
		{ "a1b2c3d first subject", "b2c3d4e second subject with spaces", "c3d4e5f third subject", "d4e5f6a fourth subject", "e5f6a7b fifth subject" },
		"Git parser formats at most five one-line entries"
	)

	local svn_output = [[
<log>
<logentry revision="12"><author>alice</author><date>2026-08-31T01:02:03.000000Z</date><msg>first &amp; important

details</msg></logentry>
<logentry revision="11"><author></author><date>2026-08-30T01:02:03.000000Z</date><msg></msg></logentry>
<logentry revision="10"><author>bob</author><date>2026-08-29T01:02:03.000000Z</date><msg>&#x65E5;&#26412;&#35486; change</msg></logentry>
<logentry revision="9"><author>carol</author><date>2026-08-28T01:02:03.000000Z</date><msg>fourth</msg></logentry>
<logentry revision="8"><author>dave</author><date>2026-08-27T01:02:03.000000Z</date><msg>fifth</msg></logentry>
<logentry revision="7"><author>erin</author><date>2026-08-26T01:02:03.000000Z</date><msg>sixth</msg></logentry>
</log>
]]
	t.deep_eq(
		log.parse_svn(svn_output),
		{ "r12 alice 2026-08-31 first & important", "r11 - 2026-08-30 (no message)", "r10 bob 2026-08-29 日本語 change", "r9 carol 2026-08-28 fourth", "r8 dave 2026-08-27 fifth" },
		"SVN parser decodes XML and formats at most five entries"
	)
	local rows = log.table_rows({ "abc123 Fix preview", "r42 user 2026-09-03 Update" })
	t.deep_eq(rows, {
		{ "Revision", "Message" },
		{ "abc123", "Fix preview" },
		{ "r42", "user 2026-09-03 Update" },
	}, "Spot rows split revision from message")
	t.deep_eq(log.table_rows({}, "No repository"), {
		{ "Revision", "Message" },
		{ "-", "No repository" },
	}, "Spot rows show bounded fallback message")
end
