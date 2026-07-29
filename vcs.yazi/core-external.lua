-- core-external.lua
-- Pure helpers for configured external diff/log commands.
local M = {}

function M.environment(env, target_family)
	env = env or {}
	if env.WSL_INTEROP or env.WSL_DISTRO_NAME or env.WSLENV then return "wsl" end
	if env.MSYSTEM or env.MSYSTEM_PREFIX or env.CYGWIN then return "git-bash" end
	if target_family == "windows" then return "windows" end
	return "linux"
end

function M.path_style(style, environment)
	if style == "native" or style == "windows" then return style end
	return environment == "wsl" and "windows" or "native"
end

function M.converter(environment)
	if environment == "wsl" then return "wslpath" end
	if environment == "git-bash" then return "cygpath" end
	return nil
end

function M.expand_args(template, context)
	local result = {}
	context = context or {}
	for _, raw in ipairs(template or {}) do
		local token = tostring(raw)
		if token == "{targets}" then
			for _, target in ipairs(context.targets or {}) do result[#result + 1] = target end
		else
			if token:find("{targets}", 1, true) then return nil, "{targets} must be a standalone argument" end
			for _, name in ipairs({ "root", "file", "revision" }) do
				local value = context[name]
				if value ~= nil then token = token:gsub("{" .. name .. "}", function() return tostring(value) end) end
			end
			result[#result + 1] = token
		end
	end
	return result
end

function M.validate(spec)
	if type(spec) ~= "table" or type(spec.command) ~= "string" or spec.command == "" then
		return false, "external command is not configured"
	end
	if spec.args ~= nil and type(spec.args) ~= "table" then return false, "external command args must be a table" end
	return true
end

return M
