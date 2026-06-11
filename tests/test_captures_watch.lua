local H = dofile("tests/helpers.lua")

local T = {}

local function full_result(result_id)
	return { resultId = result_id or "r1", matches = {}, skipped = {} }
end

T["watch() requests captures/full when semanticTokens/full goes pending"] = function()
	local client = H.fake_client({ ["kakehashi/captures/full"] = full_result() })
	local buf = H.scratch_buf()

	require("kakehashi.lsp.captures").watch({
		client = client,
		bufnr = buf,
		kind = "context",
		injection = true,
	})
	H.fire_lsp_request(client, { type = "pending", bufnr = buf, method = "textDocument/semanticTokens/full" })

	H.eq(1, #client.calls)
	H.eq("kakehashi/captures/full", client.calls[1].method)
	H.eq({
		textDocument = { uri = vim.uri_from_bufnr(buf) },
		kind = "context",
		injection = true,
	}, client.calls[1].params)
	H.eq(buf, client.calls[1].bufnr)
end

T["watch() emits KakehashiCapturesUpdate with the fresh captures as data"] = function()
	local result = full_result("r1")
	local client = H.fake_client({ ["kakehashi/captures/full"] = result })
	local buf = H.scratch_buf()
	local events = {}
	local subscription = vim.api.nvim_create_autocmd("User", {
		pattern = "KakehashiCapturesUpdate",
		callback = function(ev)
			table.insert(events, ev.data)
		end,
	})

	require("kakehashi.lsp.captures").watch({
		client = client,
		bufnr = buf,
		kind = "context",
		injection = true,
	})
	H.fire_lsp_request(client, { type = "pending", bufnr = buf, method = "textDocument/semanticTokens/full" })
	vim.api.nvim_del_autocmd(subscription)

	H.eq({ { kind = "context", injection = true, bufnr = buf, result = result } }, events)
end

T["watch() mirrors semanticTokens delta with captures/full/delta over the in-memory result"] = function()
	local function match(label)
		return { patternIndex = 0, language = "markdown", captures = {}, label = label }
	end
	local client = H.fake_client({
		["kakehashi/captures/full"] = { resultId = "r1", matches = { match("A"), match("B") }, skipped = {} },
		["kakehashi/captures/full/delta"] = {
			resultId = "r2",
			edits = { { start = 0, deleteCount = 1, data = { match("X") } } },
		},
	})
	local buf = H.scratch_buf()
	local events = {}
	local subscription = vim.api.nvim_create_autocmd("User", {
		pattern = "KakehashiCapturesUpdate",
		callback = function(ev)
			table.insert(events, ev.data)
		end,
	})

	require("kakehashi.lsp.captures").watch({ client = client, bufnr = buf, kind = "context", injection = true })
	H.fire_lsp_request(client, { type = "pending", bufnr = buf, method = "textDocument/semanticTokens/full" })
	H.fire_lsp_request(client, { type = "pending", bufnr = buf, method = "textDocument/semanticTokens/full/delta" })
	vim.api.nvim_del_autocmd(subscription)

	H.eq(2, #client.calls)
	H.eq("kakehashi/captures/full/delta", client.calls[2].method)
	-- the delta request carries no injection: the lineage identifies the mode
	H.eq({
		textDocument = { uri = vim.uri_from_bufnr(buf) },
		kind = "context",
		previousResultId = "r1",
	}, client.calls[2].params)
	H.eq(2, #events)
	H.eq({ resultId = "r2", matches = { match("X"), match("B") }, skipped = {} }, events[2].result)
end

T["watch() recovers from a stale lineage (null delta) with a fresh full request"] = function()
	local full = full_result("r9")
	local client = H.fake_client({
		["kakehashi/captures/full"] = full,
		["kakehashi/captures/full/delta"] = vim.NIL,
	})
	local buf = H.scratch_buf()
	local events = {}
	local subscription = vim.api.nvim_create_autocmd("User", {
		pattern = "KakehashiCapturesUpdate",
		callback = function(ev)
			table.insert(events, ev.data)
		end,
	})

	require("kakehashi.lsp.captures").watch({ client = client, bufnr = buf, kind = "context", injection = true })
	H.fire_lsp_request(client, { type = "pending", bufnr = buf, method = "textDocument/semanticTokens/full" })
	H.fire_lsp_request(client, { type = "pending", bufnr = buf, method = "textDocument/semanticTokens/full/delta" })
	vim.api.nvim_del_autocmd(subscription)

	H.eq(3, #client.calls)
	H.eq("kakehashi/captures/full", client.calls[3].method)
	H.eq(true, client.calls[3].params.injection) -- new full re-establishes the mode
	H.eq(2, #events)
	H.eq(full, events[2].result)
end

T["watch() falls back to captures/full when delta arrives before any result"] = function()
	local client = H.fake_client({ ["kakehashi/captures/full"] = full_result() })
	local buf = H.scratch_buf()

	require("kakehashi.lsp.captures").watch({ client = client, bufnr = buf, kind = "context" })
	H.fire_lsp_request(client, { type = "pending", bufnr = buf, method = "textDocument/semanticTokens/full/delta" })

	H.eq(1, #client.calls)
	H.eq("kakehashi/captures/full", client.calls[1].method)
end

T["watch() with the same parameters returns the live autocmd instead of stacking watchers"] = function()
	local captures = require("kakehashi.lsp.captures")
	local client = H.fake_client({ ["kakehashi/captures/full"] = full_result() })
	local buf = H.scratch_buf()
	local params = { client = client, bufnr = buf, kind = "context", injection = true }

	local autocmd = captures.watch(params)
	H.eq(autocmd, captures.watch(params), "same parameters should reuse the watcher")
	H.fire_lsp_request(client, { type = "pending", bufnr = buf, method = "textDocument/semanticTokens/full" })
	H.eq(1, #client.calls, "a reused watcher must not duplicate requests")

	local other = captures.watch({ client = client, bufnr = buf, kind = "fold", injection = true })
	assert(other ~= autocmd, "different parameters need their own watcher")

	vim.api.nvim_del_autocmd(autocmd)
	assert(captures.watch(params) ~= autocmd, "a deleted watcher should be recreated")
end

T["watch() ignores other clients, buffers, statuses, and methods"] = function()
	local client = H.fake_client({ ["kakehashi/captures/full"] = full_result() })
	local other_client = H.fake_client({})
	local buf = H.scratch_buf()
	local semantic_full = "textDocument/semanticTokens/full"

	require("kakehashi.lsp.captures").watch({ client = client, bufnr = buf, kind = "context" })
	H.fire_lsp_request(other_client, { type = "pending", bufnr = buf, method = semantic_full })
	H.fire_lsp_request(client, { type = "pending", bufnr = buf + 1, method = semantic_full })
	H.fire_lsp_request(client, { type = "complete", bufnr = buf, method = semantic_full })
	H.fire_lsp_request(client, { type = "cancel", bufnr = buf, method = semantic_full })
	H.fire_lsp_request(client, { type = "pending", bufnr = buf, method = "textDocument/hover" })

	H.eq({}, client.calls)
	H.eq({}, other_client.calls)
end

T["watch() without bufnr watches every buffer the client serves"] = function()
	local client = H.fake_client({ ["kakehashi/captures/full"] = full_result() })
	local buf1 = H.scratch_buf()
	local buf2 = H.scratch_buf()
	local events = {}
	local subscription = vim.api.nvim_create_autocmd("User", {
		pattern = "KakehashiCapturesUpdate",
		callback = function(ev)
			table.insert(events, ev.data)
		end,
	})

	require("kakehashi.lsp.captures").watch({ client = client, kind = "context" })
	H.fire_lsp_request(client, { type = "pending", bufnr = buf1, method = "textDocument/semanticTokens/full" })
	H.fire_lsp_request(client, { type = "pending", bufnr = buf2, method = "textDocument/semanticTokens/full" })
	vim.api.nvim_del_autocmd(subscription)

	H.eq(2, #client.calls)
	H.eq(vim.uri_from_bufnr(buf1), client.calls[1].params.textDocument.uri)
	H.eq(buf1, client.calls[1].bufnr)
	H.eq(vim.uri_from_bufnr(buf2), client.calls[2].params.textDocument.uri)
	H.eq(buf2, client.calls[2].bufnr)
	H.eq(buf1, events[1].bufnr)
	H.eq(buf2, events[2].bufnr)
end

return T
