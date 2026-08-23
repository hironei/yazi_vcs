-- core-fetcher.lua
-- Isolates Yazi's `UnstableFetcher` result contract (requirements §8.7.2,
-- design §3) so that `main.lua` and the Git/SVN backends never construct a
-- `ya.co()`/`coroutine.yield()` result themselves. Every function here
-- yields once per entry in `job.files` (the original list Yazi passed in,
-- not any deduplicated query list a caller built for its own CLI call) and
-- returns the coroutine `ya.co()` produces.
local M = {}

--- Success path. VCS status can change from outside Yazi at any time, so a
--- successful fetch stays retryable rather than being treated as final —
--- matching the official `git.yazi` 26.8.15 fetcher (requirements Appendix A).
---@param job table Yazi fetcher job (`{ files = ... }`)
function M.retry(job)
	return ya.co(function()
		for _, file in ipairs(job.files) do
			coroutine.yield(file, { retry = true })
		end
	end)
end

--- VCS-external directory, or nothing to fetch. Mirrors the official
--- `git.yazi`'s delegation to Yazi's built-in `noop` fetcher
--- (`yazi-plugin/preset/plugins/noop.lua`): yield with no `retry` key, so
--- Yazi does not keep re-invoking `fetch` for a location nothing will
--- change on its own. Status changes made by this plugin's own mutating
--- operations are picked up via the existing explicit `ya.emit("refresh")`
--- path instead (requirements §9), not by fetcher retry.
---@param job table
function M.noop(job)
	return ya.co(function()
		for _, file in ipairs(job.files) do
			coroutine.yield(file, {})
		end
	end)
end

--- Runner/backend failure. Logs like the official `git.yazi` does on a
--- `Command:spawn()` failure (`ya.err(...)`, not a user-facing notification)
--- and then completes the same way `noop` does, so a persistent failure
--- does not retry indefinitely.
---@param job table
---@param err any
function M.error(job, err)
	ya.err(tostring(err))
	return M.noop(job)
end

return M
