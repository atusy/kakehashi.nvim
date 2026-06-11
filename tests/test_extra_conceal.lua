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

T["conceal() watches highlights and conceals captures carrying conceal metadata"] = function()
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

	require("kakehashi.extra").conceal({ client = client, bufnr = buf })
	H.fire_lsp_request(client, { type = "pending", bufnr = buf, method = "textDocument/semanticTokens/full" })

	H.eq("kakehashi/captures/full", client.calls[1].method)
	H.eq("highlights", client.calls[1].params.kind)
	H.eq(true, client.calls[1].params.injection, "conceal needs injected layers (e.g. markdown_inline) by default")
	H.eq({
		{ row = 0, col = 0, end_row = 0, end_col = 1, conceal = "" },
		{ row = 1, col = 3, end_row = 1, end_col = 8, conceal = "…" },
	}, get_conceal_marks(buf))
end

return T
