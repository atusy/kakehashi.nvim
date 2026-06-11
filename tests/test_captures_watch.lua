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

return T
