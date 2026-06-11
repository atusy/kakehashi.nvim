local H = dofile("tests/helpers.lua")

local T = {}

local function range(start_line, start_char, end_line, end_char)
	return {
		start = { line = start_line, character = start_char },
		["end"] = { line = end_line, character = end_char },
	}
end

local function capture(rng, metadata)
	return { name = "commentstring", node = { id = "n", kind = "x" }, range = rng, metadata = metadata }
end

---@param matches table[]
local function full_result(matches)
	return { resultId = "r1", matches = matches, skipped = {} }
end

local function markdown_and_lua_client()
	return H.fake_client({
		["kakehashi/captures/full"] = full_result({
			{
				patternIndex = 0,
				language = "markdown",
				captures = { capture(range(0, 0, 50, 0), { commentstring = "<!-- %s -->" }) },
			},
			{
				patternIndex = 0,
				language = "lua",
				captures = { capture(range(10, 0, 20, 0), { commentstring = "-- %s" }) },
			},
		}),
	})
end

T["get() runs the commentstring query and returns the innermost containing value"] = function()
	local client = markdown_and_lua_client()
	local buf = H.scratch_buf()

	local commentstring = require("kakehashi.extra.commentstring").get({
		client = client,
		bufnr = buf,
		range = range(12, 0, 12, 4),
	})

	H.eq(1, #client.calls)
	H.eq("kakehashi/captures/full", client.calls[1].method)
	H.eq({
		textDocument = { uri = vim.uri_from_bufnr(buf) },
		kind = "commentstring",
		injection = true,
	}, client.calls[1].params)
	H.eq("-- %s", commentstring)
end

T["match-level #set! applies to captures without their own metadata"] = function()
	local client = H.fake_client({
		["kakehashi/captures/full"] = full_result({
			{
				patternIndex = 0,
				language = "javascript",
				captures = { capture(range(0, 0, 50, 0)) },
				metadata = { commentstring = "// %s" },
			},
			{
				patternIndex = 1,
				language = "javascript",
				-- capture-level metadata wins over the match-level value
				captures = { capture(range(5, 0, 9, 0), { commentstring = "{/* %s */}" }) },
				metadata = { commentstring = "// %s" },
			},
		}),
	})

	local commentstring = require("kakehashi.extra.commentstring").get({
		client = client,
		bufnr = H.scratch_buf(),
		range = range(6, 0, 6, 0),
	})

	H.eq("{/* %s */}", commentstring)
end

T["captures that do not contain the whole range are ignored"] = function()
	local client = H.fake_client({
		["kakehashi/captures/full"] = full_result({
			{
				patternIndex = 0,
				language = "lua",
				captures = { capture(range(10, 0, 20, 0), { commentstring = "-- %s" }) },
			},
		}),
	})
	local get = require("kakehashi.extra.commentstring").get

	-- starts inside the capture but ends past it
	H.eq(nil, get({ client = client, bufnr = H.scratch_buf(), range = range(12, 0, 25, 0) }))
	-- entirely outside
	H.eq(nil, get({ client = client, bufnr = H.scratch_buf(), range = range(30, 0, 30, 0) }))
end

T["get() returns nil on a null result (no language has the kind query)"] = function()
	local client = H.fake_client({ ["kakehashi/captures/full"] = vim.NIL })
	H.eq(
		nil,
		require("kakehashi.extra.commentstring").get({
			client = client,
			bufnr = H.scratch_buf(),
			range = range(0, 0, 0, 0),
		})
	)
end

T["get() defaults the range to the cursor position in the client's encoding"] = function()
	local client = H.fake_client({
		["kakehashi/captures/full"] = full_result({
			{
				patternIndex = 0,
				language = "markdown",
				captures = {
					-- the cursor sits on the backtick after あい: byte column 6,
					-- UTF-16 character 2 — contained by the second capture only
					capture(range(0, 0, 0, 1), { commentstring = "wrong" }),
					capture(range(0, 2, 0, 4), { commentstring = "right" }),
				},
			},
		}),
	})
	local buf = H.scratch_buf()
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "あい`x`" })
	vim.api.nvim_win_set_buf(0, buf)
	vim.api.nvim_win_set_cursor(0, { 1, 6 })

	H.eq("right", require("kakehashi.extra.commentstring").get({ client = client, bufnr = buf }))
end

T["watch() is just the captures watcher on kind commentstring"] = function()
	local client = H.fake_client({})
	local buf = H.scratch_buf()
	local commentstring = require("kakehashi.extra.commentstring")

	local autocmd = commentstring.watch({ client = client, bufnr = buf })
	H.eq(
		autocmd,
		require("kakehashi.lsp.captures").watch({
			kind = "commentstring",
			client = client,
			bufnr = buf,
			injection = true,
		}),
		"watch() should share the captures watcher, not wrap it in another layer"
	)
	H.eq(autocmd, commentstring.watch({ client = client, bufnr = buf }))
end

T["a watched get() continues the delta lineage instead of full traversals"] = function()
	local client = H.fake_client({
		["kakehashi/captures/full"] = full_result({
			{
				patternIndex = 0,
				language = "markdown",
				captures = { capture(range(0, 0, 50, 0), { commentstring = "<!-- %s -->" }) },
			},
			{
				patternIndex = 0,
				language = "lua",
				captures = { capture(range(10, 0, 20, 0), { commentstring = "-- %s" }) },
			},
		}),
		-- empty edits: the document still matches the previous result
		["kakehashi/captures/full/delta"] = { resultId = "r2", edits = {} },
	})
	local buf = H.scratch_buf()
	local commentstring = require("kakehashi.extra.commentstring")

	commentstring.watch({ client = client, bufnr = buf })
	H.fire_lsp_request(client, { type = "pending", bufnr = buf, method = "textDocument/semanticTokens/full" })
	H.eq(1, #client.calls)
	H.eq("kakehashi/captures/full", client.calls[1].method)

	H.eq("-- %s", commentstring.get({ client = client, bufnr = buf, range = range(12, 0, 12, 0) }))
	H.eq(2, #client.calls)
	H.eq("kakehashi/captures/full/delta", client.calls[2].method)
	H.eq("r1", client.calls[2].params.previousResultId, "get() should delta from the watcher's result")

	H.eq("<!-- %s -->", commentstring.get({ client = client, bufnr = buf, range = range(30, 0, 30, 0) }))
	H.eq("r2", client.calls[3].params.previousResultId, "the lineage should continue from get()'s own result")
end

T["create_pre_hook() consults the commented lines for Comment.nvim"] = function()
	local client = H.fake_client({
		["kakehashi/captures/full"] = full_result({
			{
				patternIndex = 0,
				language = "javascript",
				captures = { capture(range(0, 0, 50, 0)) },
				metadata = { commentstring = "// %s" },
			},
			{
				patternIndex = 1,
				language = "javascript",
				captures = { capture(range(10, 4, 20, 10), { commentstring = "{/* %s */}" }) },
			},
		}),
	})
	local buf = H.scratch_buf()
	local lines = {}
	for i = 1, 40 do
		lines[i] = "    <p>L" .. i .. "</p>"
	end
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	local hook = require("kakehashi.extra.commentstring").create_pre_hook({ client = client, bufnr = buf })

	-- linewise rows inside the jsx element (1-based, like Comment.nvim's ctx):
	-- only resolves to the inner capture because indentation is excluded
	H.eq("{/* %s */}", hook({ ctype = 1, range = { srow = 12, scol = 0, erow = 13, ecol = 0 } }))

	-- rows spanning out of the element fall to the outer context
	H.eq("// %s", hook({ ctype = 1, range = { srow = 12, scol = 0, erow = 30, ecol = 0 } }))
end

T["create_pre_hook() refuses linewise-only values for blockwise"] = function()
	local function client_with(commentstring)
		return H.fake_client({
			["kakehashi/captures/full"] = full_result({
				{
					patternIndex = 0,
					language = "x",
					captures = { capture(range(0, 0, 50, 0), { commentstring = commentstring }) },
				},
			}),
		})
	end
	local create = require("kakehashi.extra.commentstring").create_pre_hook
	local ctx = { ctype = 2, range = { srow = 1, scol = 0, erow = 1, ecol = 0 } }

	local lua_hook = create({ client = client_with("-- %s"), bufnr = H.scratch_buf() })
	H.eq(nil, lua_hook(ctx), "a value with no closing side cannot comment a block")

	local jsx_hook = create({ client = client_with("{/* %s */}"), bufnr = H.scratch_buf() })
	H.eq("{/* %s */}", jsx_hook(ctx))
end

T["create_pre_hook() returns nil when no kakehashi client serves the buffer"] = function()
	local hook = require("kakehashi.extra.commentstring").create_pre_hook()
	vim.api.nvim_win_set_buf(0, H.scratch_buf())
	H.eq(nil, hook({ ctype = 1, range = { srow = 1, scol = 0, erow = 1, ecol = 0 } }))
end

return T
