return function(t)
	local changes = require("core-changes")

	t.deep_eq(
		changes.list({
			["z.txt"] = "modified",
			["a.txt"] = "untracked",
			["ignored.log"] = "ignored",
			["clean.txt"] = "clean",
			["gone.txt"] = "deleted",
		}),
		{
			{ path = "a.txt", status = "untracked" },
			{ path = "gone.txt", status = "deleted" },
			{ path = "z.txt", status = "modified" },
		},
		"changed list includes supported statuses and excludes clean/ignored"
	)

	local tracked, untracked = changes.partition({ "a.txt", "new.txt", "gone.txt" }, {
		["a.txt"] = "modified",
		["new.txt"] = "untracked",
		["gone.txt"] = "deleted",
	})
	t.deep_eq(tracked, { "a.txt", "gone.txt" }, "tracked paths remain in the normal diff group")
	t.deep_eq(untracked, { "new.txt" }, "untracked paths are isolated for no-index diff")
end
