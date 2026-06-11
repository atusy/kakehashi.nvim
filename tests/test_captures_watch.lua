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

T["watch() falls back to captures/full when delta arrives before any result"] = function()
	local client = H.fake_client({ ["kakehashi/captures/full"] = full_result() })
	local buf = H.scratch_buf()

	require("kakehashi.lsp.captures").watch({ client = client, bufnr = buf, kind = "context" })
	H.fire_lsp_request(client, { type = "pending", bufnr = buf, method = "textDocument/semanticTokens/full/delta" })

	H.eq(1, #client.calls)
	H.eq("kakehashi/captures/full", client.calls[1].method)
end

return T
