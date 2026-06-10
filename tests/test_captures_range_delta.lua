local H = dofile("tests/helpers.lua")

local T = {}

local RANGE = { start = { line = 0, character = 0 }, ["end"] = { line = 10, character = 0 } }

local function match(label)
	return { patternIndex = 0, language = "markdown", captures = {}, label = label }
end

T["get() with opts.range requests kakehashi/captures/range"] = function()
	local result = { matches = { match("A") }, skipped = {} }
	local client = H.fake_client({ ["kakehashi/captures/range"] = result })
	local buf = H.scratch_buf()

	local captures = require("kakehashi.lsp.captures").get({
		client = client,
		bufnr = buf,
		kind = "context",
		range = RANGE,
		injection = true,
	})

	H.eq(1, #client.calls)
	H.eq("kakehashi/captures/range", client.calls[1].method)
	H.eq({
		textDocument = { uri = vim.uri_from_bufnr(buf) },
		kind = "context",
		range = RANGE,
		injection = true,
	}, client.calls[1].params)
	H.eq(result, captures)
end

T["get() with opts.previousResult requests full/delta without injection"] = function()
	local client = H.fake_client({
		["kakehashi/captures/full/delta"] = { resultId = "r2", matches = { match("A") }, skipped = {} },
	})
	local buf = H.scratch_buf()

	require("kakehashi.lsp.captures").get({
		client = client,
		bufnr = buf,
		kind = "context",
		injection = true,
		previousResult = { resultId = "r1", matches = {}, skipped = {} },
	})

	H.eq("kakehashi/captures/full/delta", client.calls[1].method)
	-- the delta request carries no injection: the lineage (previousResultId)
	-- already identifies the mode
	H.eq({
		textDocument = { uri = vim.uri_from_bufnr(buf) },
		kind = "context",
		previousResultId = "r1",
	}, client.calls[1].params)
end

T["delta answering with a full result returns it as-is"] = function()
	local full = { resultId = "r2", matches = { match("A") }, skipped = {} }
	local client = H.fake_client({ ["kakehashi/captures/full/delta"] = full })

	local captures = require("kakehashi.lsp.captures").get({
		client = client,
		bufnr = H.scratch_buf(),
		kind = "context",
		previousResult = { resultId = "r1", matches = {}, skipped = {} },
	})

	H.eq(full, captures)
end

T["delta edits are spliced over previous matches into a new full"] = function()
	local previous = {
		resultId = "r1",
		matches = { match("A"), match("B"), match("C"), match("D") },
		skipped = { { language = "markdown", startLine = 1, endLine = 2, reason = "boom" } },
	}
	local client = H.fake_client({
		["kakehashi/captures/full/delta"] = {
			resultId = "r2",
			edits = {
				-- indices are 0-based match indices into the previous array:
				-- delete A, then replace C with X and Y
				{ start = 0, deleteCount = 1, data = {} },
				{ start = 2, deleteCount = 1, data = { match("X"), match("Y") } },
			},
		},
	})

	local captures = require("kakehashi.lsp.captures").get({
		client = client,
		bufnr = H.scratch_buf(),
		kind = "context",
		previousResult = previous,
	})

	H.eq("r2", captures.resultId)
	H.eq(
		{ "B", "X", "Y", "D" },
		vim.tbl_map(function(m)
			return m.label
		end, captures.matches)
	)
	H.eq(previous.skipped, captures.skipped) -- skipped carries over from the previous full
	H.eq({ "A", "B", "C", "D" }, vim.tbl_map(function(m)
		return m.label
	end, previous.matches)) -- previousResult is not mutated
end

T["empty edits reproduce the previous matches with the fresh resultId"] = function()
	local previous = { resultId = "r1", matches = { match("A") }, skipped = {} }
	local client = H.fake_client({
		["kakehashi/captures/full/delta"] = { resultId = "r2", edits = {} },
	})

	local captures = require("kakehashi.lsp.captures").get({
		client = client,
		bufnr = H.scratch_buf(),
		kind = "context",
		previousResult = previous,
	})

	H.eq({ resultId = "r2", matches = { match("A") }, skipped = {} }, captures)
end

T["stale lineage (null delta) falls back to a fresh full request"] = function()
	local full = { resultId = "r9", matches = { match("Z") }, skipped = {} }
	local client = H.fake_client({
		["kakehashi/captures/full/delta"] = vim.NIL,
		["kakehashi/captures/full"] = full,
	})
	local buf = H.scratch_buf()

	local captures = require("kakehashi.lsp.captures").get({
		client = client,
		bufnr = buf,
		kind = "context",
		injection = true,
		previousResult = { resultId = "gone", matches = {}, skipped = {} },
	})

	H.eq(2, #client.calls)
	H.eq("kakehashi/captures/full", client.calls[2].method)
	H.eq(true, client.calls[2].params.injection) -- new full re-establishes the mode
	H.eq(full, captures)
end

T["range and previousResult are mutually exclusive"] = function()
	local ok, err = pcall(function()
		require("kakehashi.lsp.captures").get({
			client = H.fake_client({}),
			bufnr = H.scratch_buf(),
			kind = "context",
			range = RANGE,
			previousResult = { resultId = "r1", matches = {}, skipped = {} },
		})
	end)
	assert(not ok, "expected an error")
	assert(tostring(err):find("previousResult"), "error should explain the conflict: " .. tostring(err))
end

return T
