return function(t)
	-- `core-fetcher.lua` calls `ya.co(fn)` at the point each `Fetcher.*`
	-- function runs (not at require time), so a plain passthrough stub that
	-- turns `fn` into a real coroutine is enough to drive it with
	-- `coroutine.resume` and inspect every `coroutine.yield(file, opts)`.
	local old_ya = _G.ya
	_G.ya = { co = function(fn) return coroutine.create(fn) end }
	local fetcher = require("core-fetcher")
	_G.ya = old_ya

	--- Resume `co` until it completes, collecting every yielded (file, opts)
	--- pair. Returns fewer results than expected if the coroutine dies
	--- early (e.g. a Lua error), which the caller's count assertion catches.
	local function drain(co)
		local results = {}
		while true do
			local ok, a, b = coroutine.resume(co)
			if not ok then error(a, 0) end
			if coroutine.status(co) == "dead" then break end
			results[#results + 1] = { file = a, opts = b }
		end
		return results
	end

	do
		_G.ya = { co = function(fn) return coroutine.create(fn) end }
		local job = { files = { "a.txt", "b.txt", "c.txt" } }
		local co = fetcher.retry(job)
		local results = drain(co)
		_G.ya = old_ya

		t.eq(#results, 3, "retry yields once per job.files entry")
		for i, file in ipairs(job.files) do
			t.eq(results[i].file, file, "retry yields the exact job.files entries, in order")
			t.eq(results[i].opts.retry, true, "retry yields {retry=true}")
		end
		t.eq(coroutine.status(co), "dead", "retry leaves no incomplete coroutine")
	end

	do
		-- Requirements §8.7.2: a 0-file job is a legal, immediately-completing case.
		_G.ya = { co = function(fn) return coroutine.create(fn) end }
		local co = fetcher.retry({ files = {} })
		local results = drain(co)
		_G.ya = old_ya

		t.eq(#results, 0, "retry with zero files yields nothing")
		t.eq(coroutine.status(co), "dead", "retry with zero files completes immediately")
	end

	do
		-- VCS-external / nothing-to-fetch path: mirrors the official
		-- git.yazi's delegation to Yazi's built-in noop fetcher, which
		-- yields a bare {} (no retry key) per file.
		_G.ya = { co = function(fn) return coroutine.create(fn) end }
		local job = { files = { "a.txt", "b.txt" } }
		local co = fetcher.noop(job)
		local results = drain(co)
		_G.ya = old_ya

		t.eq(#results, 2, "noop yields once per job.files entry")
		for i, file in ipairs(job.files) do
			t.eq(results[i].file, file, "noop yields the exact job.files entries")
			t.deep_eq(results[i].opts, {}, "noop yields {} (no retry key)")
		end
		t.eq(coroutine.status(co), "dead", "noop leaves no incomplete coroutine")
	end

	do
		-- Runner/backend failure path: logs like the official git.yazi does
		-- (ya.err, not a user notification) and then completes exactly like
		-- noop, so a persistent failure does not retry forever.
		local logged
		_G.ya = {
			co = function(fn) return coroutine.create(fn) end,
			err = function(msg) logged = msg end,
		}
		local job = { files = { "a.txt" } }
		local co = fetcher.error(job, "cannot run `git status`: boom")
		local results = drain(co)
		_G.ya = old_ya

		t.eq(logged, "cannot run `git status`: boom", "error logs the message via ya.err")
		t.eq(#results, 1, "error still yields once per job.files entry")
		t.deep_eq(results[1].opts, {}, "error completes with the same shape as noop (no retry)")
		t.eq(coroutine.status(co), "dead", "error leaves no incomplete coroutine")
	end

	do
		-- Error path must complete even with multiple files queued.
		_G.ya = {
			co = function(fn) return coroutine.create(fn) end,
			err = function(_) end,
		}
		local job = { files = { "a.txt", "b.txt", "c.txt" } }
		local co = fetcher.error(job, "boom")
		local results = drain(co)
		_G.ya = old_ya

		t.eq(#results, 3, "error yields once per job.files entry even with multiple files")
		t.eq(coroutine.status(co), "dead", "error with multiple files leaves no incomplete coroutine")
	end
end
