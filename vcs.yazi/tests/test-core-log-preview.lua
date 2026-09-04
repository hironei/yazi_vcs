return function(t)
	local log = require("core-log-preview")

	t.eq(log.LIMIT, 5, "log preview has a fixed five-entry limit")
	t.eq(log.message(nil, "outside-repository"), "No Git or SVN repository.", "VCS-outside message is explanatory")
	t.eq(log.message(nil, "untracked"), "Untracked files have no history.", "untracked message is explanatory")
	t.eq(log.message(nil, "empty"), "No history for the hovered item.", "empty-history message is explanatory")
	t.eq(log.message("svn", "command-failed", "exit code 1"), "SVN log failed: exit code 1", "command failure message includes the backend")
	t.deep_eq(
		log.git_args("dir/a b.txt"),
		{ "--no-pager", "log", "-n", "5", "--date=short", "--format=%h%x09%ad%x09%s", "--", "dir/a b.txt" },
		"Git log keeps the relative path as one argument"
	)
	t.deep_eq(log.svn_args("日本語/-dash.txt"), { "log", "--xml", "-l", "5", "--", "日本語/-dash.txt" }, "SVN log keeps path boundaries")
	t.deep_eq(log.git_args(""), { "--no-pager", "log", "-n", "5", "--date=short", "--format=%h%x09%ad%x09%s", "--", "." }, "root Git log uses dot")
	t.deep_eq(log.svn_args(""), { "log", "--xml", "-l", "5", "--", "." }, "root SVN log uses dot")

	local git_output = table.concat({
		"a1b2c3d\t2026-08-31\tfirst subject",
		"b2c3d4e\t2026-08-30\tsecond subject with spaces",
		"c3d4e5f\t2026-08-29\tthird subject",
		"d4e5f6a\t2026-08-28\tfourth subject",
		"e5f6a7b\t2026-08-27\tfifth subject",
		"f6a7b8c\t2026-08-26\tsixth subject must be ignored",
	}, "\n")
	t.deep_eq(
		log.parse_git(git_output),
		{
			{ date = "2026-08-31", revision = "a1b2c3d", message = "first subject" },
			{ date = "2026-08-30", revision = "b2c3d4e", message = "second subject with spaces" },
			{ date = "2026-08-29", revision = "c3d4e5f", message = "third subject" },
			{ date = "2026-08-28", revision = "d4e5f6a", message = "fourth subject" },
			{ date = "2026-08-27", revision = "e5f6a7b", message = "fifth subject" },
		},
		"Git parser returns date, revision, and message for at most five entries"
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
		{
			{ author = "alice", date = "2026-08-31", message = "first & important", revision = "r12" },
			{ author = "-", date = "2026-08-30", message = "(no message)", revision = "r11" },
			{ author = "bob", date = "2026-08-29", message = "日本語 change", revision = "r10" },
			{ author = "carol", date = "2026-08-28", message = "fourth", revision = "r9" },
			{ author = "dave", date = "2026-08-27", message = "fifth", revision = "r8" },
		},
		"SVN parser returns date, revision, and message for at most five entries"
	)
	t.eq(log.format({ revision = "abc123", message = "Fix preview" }), "abc123 Fix preview", "Git notification format remains unchanged")
	t.eq(log.format({ author = "user", date = "2026-09-03", message = "Update", revision = "r42" }), "r42 user 2026-09-03 Update", "SVN notification format remains unchanged")
	local rows = log.table_rows({
		{ date = "2026-09-03", revision = "abc123", message = "Fix preview" },
		{ date = "2026-09-02", revision = "r42", message = "Update" },
	})
	t.deep_eq(rows, {
		{ "Date", "Revision", "Message" },
		{ "2026-09-03", "abc123", "Fix preview" },
		{ "2026-09-02", "r42", "Update" },
	}, "Spot rows expose date, revision, and message separately")
	t.deep_eq(log.table_rows({}, "No repository"), {
		{ "Date", "Revision", "Message" },
		{ "-", "-", "No repository" },
	}, "Spot rows show bounded fallback message")
end
