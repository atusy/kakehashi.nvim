local H = dofile("tests/helpers.lua")

local T = {}

T["get() defaults position to the cursor (UTF-16)"] = function()
	local client = H.fake_client({ ["kakehashi/node"] = { id = "n", kind = "k" } })
	local buf = H.scratch_buf()
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "abc", "あいう_x" })
	vim.api.nvim_win_set_buf(0, buf)
	vim.api.nvim_win_set_cursor(0, { 2, 9 }) -- on "_", byte 9, after 3 multibyte chars

	require("kakehashi.lsp.node").get({ client = client })

	H.eq({ line = 1, character = 3 }, client.calls[1].params.position)
	H.eq(buf, client.calls[1].bufnr)
end

T["get() defaults client to the kakehashi client attached to the buffer"] = function()
	local fake = H.fake_client({ ["kakehashi/node"] = { id = "n", kind = "k" } })
	local buf = H.scratch_buf()
	local original = vim.lsp.get_clients
	vim.lsp.get_clients = function(filter)
		H.eq({ bufnr = buf, name = "kakehashi" }, filter)
		return { fake }
	end
	local ok, err = pcall(function()
		local node = require("kakehashi.lsp.node").get({
			bufnr = buf,
			position = { line = 0, character = 0 },
		})
		H.eq("n", node.id)
		H.eq("kakehashi/node", fake.calls[1].method)
	end)
	vim.lsp.get_clients = original
	assert(ok, err)
end

T["get() errors clearly when no kakehashi client is attached"] = function()
	local buf = H.scratch_buf()
	local original = vim.lsp.get_clients
	vim.lsp.get_clients = function()
		return {}
	end
	local ok, err = pcall(function()
		require("kakehashi.lsp.node").get({ bufnr = buf, position = { line = 0, character = 0 } })
	end)
	vim.lsp.get_clients = original
	assert(not ok, "expected an error")
	assert(tostring(err):find("kakehashi"), "error should mention kakehashi: " .. tostring(err))
end

return T
