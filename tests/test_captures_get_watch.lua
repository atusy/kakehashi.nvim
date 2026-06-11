local H = dofile("tests/helpers.lua")

local T = {}

local function match(label)
	return { patternIndex = 0, language = "markdown", captures = {}, label = label }
end

T["get() continues the delta lineage of a watcher observing the target"] = function()
	local client = H.fake_client({
		["kakehashi/captures/full"] = { resultId = "r1", matches = { match("A"), match("B") }, skipped = {} },
		["kakehashi/captures/full/delta"] = {
			resultId = "r2",
			edits = { { start = 0, deleteCount = 1, data = { match("X") } } },
		},
	})
	local buf = H.scratch_buf()
	local captures = require("kakehashi.lsp.captures")

	captures.watch({ client = client, bufnr = buf, kind = "context", injection = true }) -- seeds r1

	local result = captures.get({ client = client, bufnr = buf, kind = "context", injection = true })

	H.eq(2, #client.calls)
	H.eq("kakehashi/captures/full/delta", client.calls[2].method)
	H.eq("r1", client.calls[2].params.previousResultId)
	H.eq({ resultId = "r2", matches = { match("X"), match("B") }, skipped = {} }, result)
end

T["get() hands its fresh result back to the watcher as the new lineage"] = function()
	local client = H.fake_client({
		["kakehashi/captures/full"] = { resultId = "r1", matches = { match("A") }, skipped = {} },
		["kakehashi/captures/full/delta"] = { resultId = "r2", edits = {} },
	})
	local buf = H.scratch_buf()
	local captures = require("kakehashi.lsp.captures")

	captures.watch({ client = client, bufnr = buf, kind = "context", injection = true }) -- seeds r1
	captures.get({ client = client, bufnr = buf, kind = "context", injection = true }) -- delta to r2
	H.fire_lsp_request(client, { type = "pending", bufnr = buf, method = "textDocument/semanticTokens/full/delta" })

	H.eq(3, #client.calls)
	H.eq("kakehashi/captures/full/delta", client.calls[3].method)
	H.eq("r2", client.calls[3].params.previousResultId, "the watcher should delta from the result get() obtained")
end

T["get() seeds the lineage of a watcher that has no result yet"] = function()
	local client = H.fake_client({
		["kakehashi/captures/full"] = { resultId = "r1", matches = {}, skipped = {} },
		["kakehashi/captures/full/delta"] = { resultId = "r2", edits = {} },
	})
	local buf = H.scratch_buf()
	local captures = require("kakehashi.lsp.captures")

	-- an all-buffer watcher cannot seed buffers it cannot see
	captures.watch({ client = client, kind = "context", injection = true })
	captures.get({ client = client, bufnr = buf, kind = "context", injection = true })
	H.fire_lsp_request(client, { type = "pending", bufnr = buf, method = "textDocument/semanticTokens/full/delta" })

	H.eq(2, #client.calls)
	H.eq("kakehashi/captures/full", client.calls[1].method)
	H.eq("kakehashi/captures/full/delta", client.calls[2].method)
	H.eq("r1", client.calls[2].params.previousResultId, "the watcher should delta from the full get() obtained")
end

T["get() cooperates with an all-buffer watcher serving the target buffer"] = function()
	local client = H.fake_client({
		["kakehashi/captures/full"] = { resultId = "r1", matches = {}, skipped = {} },
		["kakehashi/captures/full/delta"] = { resultId = "r2", edits = {} },
	})
	local buf = H.scratch_buf()
	local captures = require("kakehashi.lsp.captures")

	captures.watch({ client = client, kind = "context" })
	H.fire_lsp_request(client, { type = "pending", bufnr = buf, method = "textDocument/semanticTokens/full" })
	local result = captures.get({ client = client, bufnr = buf, kind = "context" })

	H.eq(2, #client.calls)
	H.eq("kakehashi/captures/full/delta", client.calls[2].method)
	H.eq("r1", client.calls[2].params.previousResultId)
	H.eq("r2", result.resultId)
end

T["get() ignores watchers with different parameters or a range request"] = function()
	local client = H.fake_client({
		["kakehashi/captures/full"] = { resultId = "r1", matches = {}, skipped = {} },
		["kakehashi/captures/range"] = { matches = {}, skipped = {} },
	})
	local buf = H.scratch_buf()
	local captures = require("kakehashi.lsp.captures")

	captures.watch({ client = client, bufnr = buf, kind = "context", injection = true }) -- seeds r1

	-- different kind and different injection mode each miss the watcher
	captures.get({ client = client, bufnr = buf, kind = "fold", injection = true })
	captures.get({ client = client, bufnr = buf, kind = "context" })
	-- a range request on an unwatched kind goes to the server as-is
	captures.get({
		client = client,
		bufnr = buf,
		kind = "fold",
		injection = true,
		range = { start = { line = 0, character = 0 }, ["end"] = { line = 1, character = 0 } },
	})

	H.eq(4, #client.calls)
	H.eq("kakehashi/captures/full", client.calls[2].method)
	H.eq("kakehashi/captures/full", client.calls[3].method)
	H.eq("kakehashi/captures/range", client.calls[4].method)

	-- the watcher's lineage from before get() is still intact
	H.fire_lsp_request(client, { type = "pending", bufnr = buf, method = "textDocument/semanticTokens/full/delta" })
	H.eq("kakehashi/captures/full/delta", client.calls[5].method)
	H.eq("r1", client.calls[5].params.previousResultId)
end

---A match whose single capture spans the given lines.
local function match_at(label, start_line, end_line)
	return {
		patternIndex = 0,
		language = "lua",
		label = label,
		captures = {
			{
				name = "context",
				node = { id = label, kind = "x" },
				range = {
					start = { line = start_line, character = 0 },
					["end"] = { line = end_line, character = 0 },
				},
			},
		},
	}
end

local function lines_range(start_line, end_line)
	return {
		start = { line = start_line, character = 0 },
		["end"] = { line = end_line, character = 0 },
	}
end

T["get() with range serves a watched buffer via delta, filtered in memory"] = function()
	local client = H.fake_client({
		["kakehashi/captures/full"] = {
			resultId = "r1",
			matches = { match_at("A", 0, 10), match_at("B", 20, 30) },
			skipped = {},
		},
		["kakehashi/captures/full/delta"] = { resultId = "r2", edits = {} },
	})
	local buf = H.scratch_buf()
	local captures = require("kakehashi.lsp.captures")

	captures.watch({ client = client, bufnr = buf, kind = "context", injection = true }) -- seeds r1

	local result = captures.get({
		client = client,
		bufnr = buf,
		kind = "context",
		injection = true,
		range = lines_range(2, 3),
	})

	H.eq(2, #client.calls)
	H.eq("kakehashi/captures/full/delta", client.calls[2].method, "no captures/range traversal for a watched buffer")
	H.eq("r1", client.calls[2].params.previousResultId)
	-- the same shape a kakehashi/captures/range response has: no resultId
	H.eq({ matches = { match_at("A", 0, 10) }, skipped = {} }, result)

	-- the delta moved the watcher's lineage forward
	local second = captures.get({
		client = client,
		bufnr = buf,
		kind = "context",
		injection = true,
		range = lines_range(25, 25),
	})
	H.eq("r2", client.calls[3].params.previousResultId)
	H.eq({ matches = { match_at("B", 20, 30) }, skipped = {} }, second)
end

T["get() with range recovers a stale watched lineage with a fresh full"] = function()
	local client = H.fake_client({
		["kakehashi/captures/full"] = {
			resultId = "r9",
			matches = { match_at("A", 0, 10) },
			skipped = {},
		},
		["kakehashi/captures/full/delta"] = vim.NIL,
	})
	local buf = H.scratch_buf()
	local captures = require("kakehashi.lsp.captures")

	captures.watch({ client = client, bufnr = buf, kind = "context", injection = true }) -- seeds r9

	local result = captures.get({
		client = client,
		bufnr = buf,
		kind = "context",
		injection = true,
		range = lines_range(2, 3),
	})

	H.eq(3, #client.calls)
	H.eq("kakehashi/captures/full/delta", client.calls[2].method)
	H.eq("kakehashi/captures/full", client.calls[3].method, "a lost lineage re-seeds the watcher, not captures/range")
	H.eq({ matches = { match_at("A", 0, 10) }, skipped = {} }, result)
end

return T
