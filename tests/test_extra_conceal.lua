local H = dofile("tests/helpers.lua")

local T = {}

local NS = vim.api.nvim_create_namespace("kakehashi.extra.conceal")

local function capture(node_kind, range, metadata)
	return { name = "x", node = { id = node_kind, kind = node_kind }, range = range, metadata = metadata }
end

local function range(start_line, start_char, end_line, end_char)
	return {
		start = { line = start_line, character = start_char },
		["end"] = { line = end_line, character = end_char },
	}
end

local function get_conceal_marks(buf)
	return vim.tbl_map(function(mark)
		return {
			row = mark[2],
			col = mark[3],
			end_row = mark[4].end_row,
			end_col = mark[4].end_col,
			conceal = mark[4].conceal,
		}
	end, vim.api.nvim_buf_get_extmarks(buf, NS, 0, -1, { details = true }))
end

T["conceal.toggle() watches highlights and conceals captures carrying conceal metadata"] = function()
	local result = {
		resultId = "r1",
		matches = {
			{
				patternIndex = 0,
				language = "markdown_inline",
				captures = { capture("code_span_delimiter", range(0, 0, 0, 1), { conceal = "" }) },
			},
			{
				patternIndex = 1,
				language = "markdown_inline",
				-- match-level #set! applies to every capture of the pattern
				captures = { capture("link_destination", range(1, 3, 1, 8)) },
				metadata = { conceal = "…" },
			},
			{
				patternIndex = 2,
				language = "markdown",
				captures = { capture("inline", range(0, 0, 1, 0)) }, -- no conceal: no extmark
			},
		},
		skipped = {},
	}
	local client = H.fake_client({ ["kakehashi/captures/full"] = result })
	local buf = H.scratch_buf()
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "`x`", "abcdefghij" })

	require("kakehashi.extra").conceal.toggle({ client = client, bufnr = buf })
	H.fire_lsp_request(client, { type = "pending", bufnr = buf, method = "textDocument/semanticTokens/full" })

	H.eq("kakehashi/captures/full", client.calls[1].method)
	H.eq("highlights", client.calls[1].params.kind)
	H.eq(true, client.calls[1].params.injection, "conceal needs injected layers (e.g. markdown_inline) by default")
	H.eq({
		{ row = 0, col = 0, end_row = 0, end_col = 1, conceal = "" },
		{ row = 1, col = 3, end_row = 1, end_col = 8, conceal = "…" },
	}, get_conceal_marks(buf))
end

T["conceal.toggle() replaces marks on update and clears them on a null result"] = function()
	local responses = {
		{
			resultId = "r1",
			matches = {
				{
					patternIndex = 0,
					language = "markdown",
					captures = { capture("a", range(0, 0, 0, 1), { conceal = "" }) },
				},
			},
			skipped = {},
		},
		{
			resultId = "r2",
			matches = {
				{
					patternIndex = 0,
					language = "markdown",
					captures = { capture("b", range(1, 0, 1, 2), { conceal = "•" }) },
				},
			},
			skipped = {},
		},
		vim.NIL, -- e.g. the only language layer lost its highlights query
	}
	local turn = 0
	local client = H.fake_client({
		["kakehashi/captures/full"] = function()
			turn = turn + 1
			return responses[turn]
		end,
	})
	local buf = H.scratch_buf()
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "`x`", "abcdefghij" })
	local pending_full = { type = "pending", bufnr = buf, method = "textDocument/semanticTokens/full" }

	require("kakehashi.extra").conceal.toggle({ client = client, bufnr = buf })

	H.fire_lsp_request(client, pending_full)
	H.eq({ { row = 0, col = 0, end_row = 0, end_col = 1, conceal = "" } }, get_conceal_marks(buf))

	H.fire_lsp_request(client, pending_full)
	H.eq({ { row = 1, col = 0, end_row = 1, end_col = 2, conceal = "•" } }, get_conceal_marks(buf))

	H.fire_lsp_request(client, pending_full)
	H.eq({}, get_conceal_marks(buf))
end

T["conceal.toggle() turns concealing off (clearing marks) and back on"] = function()
	local result = {
		resultId = "r1",
		matches = {
			{
				patternIndex = 0,
				language = "markdown",
				captures = { capture("a", range(0, 0, 0, 1), { conceal = "" }) },
			},
		},
		skipped = {},
	}
	local client = H.fake_client({ ["kakehashi/captures/full"] = result })
	local buf = H.scratch_buf()
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "`x`" })
	local toggle = require("kakehashi.extra").conceal.toggle
	local pending_full = { type = "pending", bufnr = buf, method = "textDocument/semanticTokens/full" }

	H.eq(true, toggle({ client = client, bufnr = buf }))
	H.fire_lsp_request(client, pending_full)
	H.eq(1, #get_conceal_marks(buf))

	H.eq(false, toggle({ client = client, bufnr = buf }), "second toggle should disable")
	H.eq({}, get_conceal_marks(buf), "toggling off should clear the marks")
	H.fire_lsp_request(client, pending_full)
	H.eq({}, get_conceal_marks(buf), "a disabled applier must not re-apply marks")

	H.eq(true, toggle({ client = client, bufnr = buf }), "third toggle should re-enable")
	H.fire_lsp_request(client, pending_full)
	H.eq(1, #get_conceal_marks(buf))
end

T["conceal.toggle() tracks each parameter set independently"] = function()
	local toggle = require("kakehashi.extra").conceal.toggle
	local client = H.fake_client({})
	local buf = H.scratch_buf()

	H.eq(true, toggle({ client = client, bufnr = buf }))
	H.eq(true, toggle({ client = client }), "an all-buffer toggle is not the buffer-pinned one")
	H.eq(false, toggle({ client = client }))
	H.eq(false, toggle({ client = client, bufnr = buf }), "the buffer-pinned toggle should still be on")
end

T["conceal.toggle() converts UTF-16 positions to byte columns for extmarks"] = function()
	local result = {
		resultId = "r1",
		matches = {
			{
				patternIndex = 0,
				language = "markdown_inline",
				-- the backtick after あい: UTF-16 units 2..3, bytes 6..7
				captures = { capture("code_span_delimiter", range(0, 2, 0, 3), { conceal = "" }) },
			},
		},
		skipped = {},
	}
	local client = H.fake_client({ ["kakehashi/captures/full"] = result })
	local buf = H.scratch_buf()
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "あい`x`" })

	require("kakehashi.extra").conceal.toggle({ client = client, bufnr = buf })
	H.fire_lsp_request(client, { type = "pending", bufnr = buf, method = "textDocument/semanticTokens/full" })

	H.eq({ { row = 0, col = 6, end_row = 0, end_col = 7, conceal = "" } }, get_conceal_marks(buf))
end

return T
