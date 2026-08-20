-- core-scope.lua
-- Shared context snapshot, repository resolution, and user-facing errors.
local Context = require(".core-context")
local Detector = require(".core-detector")
local Notify = require(".core-notify")
local Targets = require(".core-targets")

local M = {}

function M.resolve(cfg)
	local context = Context.snapshot()
	return Targets.resolve(context.selected, context.cwd, context.info, function(start)
		return Detector.detect(Url(start), cfg.detection.priority)
	end)
end

function M.resolve_or_notify(cfg)
	local scope, reason = M.resolve(cfg)
	if scope then return scope end
	if reason and reason.code == "mixed" then
		Notify.error("Selected targets do not belong to the same Git or SVN working copy.")
	elseif reason and reason.code == "outside" then
		Notify.error("Refusing VCS operation outside the repository: %s", reason.path)
	else
		Notify.warn("Not inside a Git or SVN working copy.")
	end
	return nil
end

return M
