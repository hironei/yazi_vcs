-- tests/support.lua
local M = { pass = 0, fail = 0 }
M.is_windows = package.config:sub(1, 1) == "\\"

function M.shell_quote(value)
	value = tostring(value)
	if M.is_windows then
		return '"' .. value:gsub('"', '\\"') .. '"'
	end
	return "'" .. value:gsub("'", "'\\''") .. "'"
end

function M.path_join(left, right)
	return left .. (M.is_windows and "\\" or "/") .. right
end

function M.run_in_dir(dir, command)
	local cd = M.is_windows and "cd /d " or "cd "
	return os.execute(cd .. M.shell_quote(dir) .. " && " .. command)
end

function M.capture_in_dir(dir, command)
	local cd = M.is_windows and "cd /d " or "cd "
	return io.popen(cd .. M.shell_quote(dir) .. " && " .. command)
end

function M.temp_dir()
	local dir = os.tmpname()
	os.remove(dir)
	os.execute((M.is_windows and "mkdir " or "mkdir -p ") .. M.shell_quote(dir))
	return dir
end

function M.remove_tree(dir)
	return os.execute((M.is_windows and "rmdir /s /q " or "rm -rf -- ") .. M.shell_quote(dir))
end

function M.to_file_url(path)
	if M.is_windows then
		return "file:///" .. path:gsub("\\", "/")
	end
	return "file://" .. path
end

local function dump(v, seen)
	if type(v) ~= "table" then
		return tostring(v)
	end
	seen = seen or {}
	if seen[v] then
		return "..."
	end
	seen[v] = true
	local keys = {}
	for k in pairs(v) do
		keys[#keys + 1] = k
	end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	local parts = {}
	for _, k in ipairs(keys) do
		parts[#parts + 1] = tostring(k) .. "=" .. dump(v[k], seen)
	end
	return "{" .. table.concat(parts, ", ") .. "}"
end
M.dump = dump

local function deep_eq(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b end
	for k, v in pairs(a) do
		if not deep_eq(v, b[k]) then return false end
	end
	for k in pairs(b) do
		if a[k] == nil then return false end
	end
	return true
end

local function record(ok, label, detail)
	if ok then
		M.pass = M.pass + 1
	else
		M.fail = M.fail + 1
		io.stderr:write("FAIL " .. label .. (detail and (": " .. detail) or "") .. "\n")
	end
end

function M.eq(actual, expected, label)
	record(actual == expected, label or "eq", string.format("expected %s, got %s", dump(expected), dump(actual)))
end

function M.deep_eq(actual, expected, label)
	record(deep_eq(actual, expected), label or "deep_eq", string.format("expected %s, got %s", dump(expected), dump(actual)))
end

function M.truthy(v, label)
	record(not not v, label or "truthy", "expected truthy, got " .. dump(v))
end

function M.falsy(v, label)
	record(not v, label or "falsy", "expected falsy, got " .. dump(v))
end

function M.report()
	print(string.format("%d passed, %d failed", M.pass, M.fail))
	if M.fail > 0 then os.exit(1) end
end

return M
