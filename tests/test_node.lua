local H = dofile("tests/helpers.lua")

local T = {}

T["get() requests kakehashi/node and returns a KakehashiNode"] = function()
	local client = H.fake_client({
		["kakehashi/node"] = { id = "node-1", kind = "fenced_code_block" },
	})
	local buf = H.scratch_buf()

	local node = require("kakehashi.lsp.node").get({
		client = client,
		bufnr = buf,
		position = { line = 3, character = 5 },
		injection = true,
	})

	H.eq(1, #client.calls)
	H.eq("kakehashi/node", client.calls[1].method)
	H.eq({
		textDocument = { uri = vim.uri_from_bufnr(buf) },
		position = { line = 3, character = 5 },
		injection = true,
	}, client.calls[1].params)
	H.eq(buf, client.calls[1].bufnr)
	H.eq("node-1", node.id)
end

T["get() returns nil when the server resolves no node"] = function()
	local client = H.fake_client({}) -- null result
	local buf = H.scratch_buf()

	local node = require("kakehashi.lsp.node").get({
		client = client,
		bufnr = buf,
		position = { line = 0, character = 0 },
	})

	H.eq(nil, node)
end

return T
