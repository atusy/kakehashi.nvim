local H = dofile("tests/helpers.lua")

local T = {}

T["get() requests kakehashi/captures/full and returns the result"] = function()
	local result = {
		resultId = "r1",
		matches = {
			{
				patternIndex = 0,
				language = "markdown",
				captures = {
					{
						name = "context",
						node = { id = "n1", kind = "atx_heading" },
						range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 7 } },
					},
				},
			},
		},
		skipped = {},
	}
	local client = H.fake_client({ ["kakehashi/captures/full"] = result })
	local buf = H.scratch_buf()

	local captures = require("kakehashi.lsp.captures").get({
		client = client,
		bufnr = buf,
		kind = "context",
		injection = true,
	})

	H.eq("kakehashi/captures/full", client.calls[1].method)
	H.eq({
		textDocument = { uri = vim.uri_from_bufnr(buf) },
		kind = "context",
		injection = true,
	}, client.calls[1].params)
	H.eq(buf, client.calls[1].bufnr)
	H.eq(result, captures)
end

T["get() returns nil when no language has the kind query (null result)"] = function()
	local client = H.fake_client({ ["kakehashi/captures/full"] = vim.NIL })
	local captures = require("kakehashi.lsp.captures").get({
		client = client,
		bufnr = H.scratch_buf(),
		kind = "context",
	})
	H.eq(nil, captures)
end

T["get() requires a kind"] = function()
	local client = H.fake_client({})
	local ok, err = pcall(function()
		require("kakehashi.lsp.captures").get({ client = client, bufnr = H.scratch_buf() })
	end)
	assert(not ok, "expected an error")
	assert(tostring(err):find("kind"), "error should mention kind: " .. tostring(err))
end

return T
