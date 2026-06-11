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

	captures.watch({ client = client, bufnr = buf, kind = "context", injection = true })
	H.fire_lsp_request(client, { type = "pending", bufnr = buf, method = "textDocument/semanticTokens/full" })

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

	captures.watch({ client = client, bufnr = buf, kind = "context", injection = true })
	H.fire_lsp_request(client, { type = "pending", bufnr = buf, method = "textDocument/semanticTokens/full" })
	captures.get({ client = client, bufnr = buf, kind = "context", injection = true })
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

	captures.watch({ client = client, bufnr = buf, kind = "context", injection = true })
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

	captures.watch({ client = client, bufnr = buf, kind = "context", injection = true })
	H.fire_lsp_request(client, { type = "pending", bufnr = buf, method = "textDocument/semanticTokens/full" })

	-- different kind and different injection mode each miss the watcher
	captures.get({ client = client, bufnr = buf, kind = "fold", injection = true })
	captures.get({ client = client, bufnr = buf, kind = "context" })
	-- range responses carry no resultId, so they neither use nor touch the lineage
	captures.get({
		client = client,
		bufnr = buf,
		kind = "context",
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

return T
