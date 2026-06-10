local H = dofile("tests/helpers.lua")

local T = {}

T["new() wraps an existing NodeInfo (e.g. from captures) into a KakehashiNode"] = function()
	local client = H.fake_client({
		["kakehashi/node/text"] = { text = "# title" },
	})
	local buf = H.scratch_buf()

	local node = require("kakehashi.lsp.node").new(
		{ id = "from-captures", kind = "atx_heading" },
		{ client = client, bufnr = buf }
	)

	H.eq("from-captures", node.id)
	H.eq("# title", node:text())
	H.eq("from-captures", client.calls[1].params.id)
	H.eq(vim.uri_from_bufnr(buf), client.calls[1].params.textDocument.uri)
end

return T
