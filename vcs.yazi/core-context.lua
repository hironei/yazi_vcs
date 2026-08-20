-- core-context.lua
-- Capture one immutable-looking Yazi context snapshot per VCS operation.
local M = {}

M.snapshot = ya.sync(function()
	local tab, selected, info = cx.active, {}, {}
	for _, url in pairs(tab.selected) do
		local path = tostring(url)
		selected[#selected + 1] = path
		info[path] = false
	end
	for i = 1, #tab.current.files do
		local file = tab.current.files[i]
		if file then info[tostring(file.url)] = file.cha and file.cha.is_dir or false end
	end
	return {
		selected = selected,
		cwd = tostring(tab.current.cwd),
		info = info,
	}
end)

return M
