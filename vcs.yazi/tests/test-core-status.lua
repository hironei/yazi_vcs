-- tests/test-core-status.lua
return function(t)
	local status = require("core-status")

	-- Priority ordering matches requirements §8.3's tiers.
	t.truthy(status.priority("conflict") > status.priority("missing"), "conflict outranks missing")
	t.truthy(status.priority("conflict") > status.priority("deleted"), "conflict outranks deleted")
	t.truthy(status.priority("missing") > status.priority("modified"), "missing outranks modified")
	t.truthy(status.priority("deleted") > status.priority("replaced"), "deleted outranks replaced")
	t.truthy(status.priority("modified") > status.priority("added"), "modified outranks added")
	t.truthy(status.priority("replaced") > status.priority("untracked"), "replaced outranks untracked")
	t.truthy(status.priority("added") > status.priority("locked"), "added outranks locked")
	t.truthy(status.priority("untracked") > status.priority("external"), "untracked outranks external")
	t.truthy(status.priority("locked") > status.priority("ignored"), "locked outranks ignored")
	t.truthy(status.priority("external") > status.priority("ignored"), "external outranks ignored")
	t.truthy(status.priority("ignored") > status.priority("clean"), "ignored outranks clean")
	t.eq(status.priority("clean"), 0, "clean is priority 0")
	t.eq(status.display_name("excluded"), "ignored", "excluded is converted to the visible ignored status")
	t.eq(status.display_name("modified"), "modified", "ordinary statuses are unchanged for display")
	t.eq(status.priority("no-such-status"), 0, "unknown name falls back to 0 (clean)")

	-- Every real status name maps to a unique priority number (the
	-- rendering/aggregation code identifies a status by its number
	-- alone, so a collision would silently conflate two states).
	local seen = {}
	local collisions = {}
	for name, code in pairs(status.CODES) do
		if seen[code] and seen[code] ~= name then
			collisions[#collisions + 1] = seen[code] .. "/" .. name .. "=" .. code
		end
		seen[code] = name
	end
	t.eq(#collisions, 0, "no two status names share a priority number (" .. table.concat(collisions, ", ") .. ")")

	-- merge
	do
		local into = { ["a.txt"] = "modified" }
		status.merge(into, { ["a.txt"] = "clean", ["b.txt"] = "added" })
		t.deep_eq(into, { ["b.txt"] = "added" }, "merge drops clean entries and adds new ones")
	end

	-- bubble_up
	do
		local up = status.bubble_up({ ["src/components/Foo.tsx"] = "modified" })
		t.deep_eq(up, { ["src/components"] = "modified", ["src"] = "modified" }, "bubble_up marks every ancestor")
	end
	do
		local up = status.bubble_up({
			["src/a.txt"] = "modified",
			["src/b.txt"] = "conflict",
		})
		t.eq(up["src"], "conflict", "bubble_up keeps the highest-priority descendant status")
	end
	do
		local up = status.bubble_up({ ["node_modules/pkg/index.js"] = "ignored" })
		t.deep_eq(up, {}, "bubble_up does not let an ignored file mark its ancestors")
	end
	do
		local up = status.bubble_up({ ["top.txt"] = "modified" })
		t.deep_eq(up, {}, "bubble_up produces nothing for a file directly at the root")
	end

	-- propagate_down
	do
		local down = status.propagate_down({ "node_modules" }, "")
		t.deep_eq(down, { ["node_modules"] = "ignored" }, "propagate_down marks a direct ignored child of the fetched dir")
	end
	do
		local down = status.propagate_down({ "node_modules" }, "node_modules")
		t.deep_eq(down, { ["node_modules"] = "excluded" }, "propagate_down marks cwd itself when it is the ignored dir")
	end
	do
		local down = status.propagate_down({ "node_modules" }, "node_modules/sub")
		t.deep_eq(down, { ["node_modules/sub"] = "excluded" }, "propagate_down marks cwd when it is inside the ignored dir")
	end
	do
		local down = status.propagate_down({ "src/vendor" }, "")
		t.deep_eq(down, {}, "propagate_down does not mark an indirect (non-direct-child) ignored dir")
	end
	do
		local down = status.propagate_down({}, "")
		t.deep_eq(down, {}, "propagate_down with no excluded dirs produces nothing")
	end
end
