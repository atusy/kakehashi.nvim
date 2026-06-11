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
local function result_with(matches)
	return { matches = matches, skipped = {} }
end

T["get() returns the innermost containing capture's commentstring metadata"] = function()
	local client = H.fake_client({
		["kakehashi/captures/range"] = result_with({
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
	local buf = H.scratch_buf()
	local target = range(12, 0, 12, 4)

	local commentstring = require("kakehashi.extra.commentstring").get({
		client = client,
		bufnr = buf,
		range = target,
	})

	H.eq(1, #client.calls)
	H.eq("kakehashi/captures/range", client.calls[1].method)
	H.eq({
		textDocument = { uri = vim.uri_from_bufnr(buf) },
		kind = "commentstring",
		range = target,
		injection = true,
	}, client.calls[1].params)
	H.eq("-- %s", commentstring)
end

T["match-level #set! applies to captures without their own metadata"] = function()
	local client = H.fake_client({
		["kakehashi/captures/range"] = result_with({
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
		["kakehashi/captures/range"] = result_with({
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
	local client = H.fake_client({ ["kakehashi/captures/range"] = vim.NIL })
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
	local client = H.fake_client({ ["kakehashi/captures/range"] = result_with({}) })
	local buf = H.scratch_buf()
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "あい`x`" })
	vim.api.nvim_win_set_buf(0, buf)
	-- the backtick after あい: byte column 6, UTF-16 character 2
	vim.api.nvim_win_set_cursor(0, { 1, 6 })

	require("kakehashi.extra.commentstring").get({ client = client, bufnr = buf })

	H.eq(range(0, 2, 0, 2), client.calls[1].params.range)
end

---A full-document result as the captures watcher publishes it.
local function full_result_with(matches)
	return { resultId = "r1", matches = matches, skipped = {} }
end

T["watch() lets get() answer from the watcher's results without a request"] = function()
	local client = H.fake_client({
		["kakehashi/captures/full"] = full_result_with({
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
	local buf = H.scratch_buf()
	vim.bo[buf].commentstring = "# %s"
	local commentstring = require("kakehashi.extra.commentstring")

	commentstring.watch({ client = client, bufnr = buf })
	H.fire_lsp_request(client, { type = "pending", bufnr = buf, method = "textDocument/semanticTokens/full" })

	H.eq(1, #client.calls)
	H.eq("kakehashi/captures/full", client.calls[1].method)
	H.eq("commentstring", client.calls[1].params.kind)

	H.eq("-- %s", commentstring.get({ client = client, bufnr = buf, range = range(12, 0, 12, 4) }))
	H.eq("<!-- %s -->", commentstring.get({ client = client, bufnr = buf, range = range(30, 0, 30, 0) }))
	H.eq(nil, commentstring.get({ client = client, bufnr = buf, range = range(60, 0, 60, 0) }))
	H.eq(1, #client.calls, "watched get() must not send requests of its own")
	H.eq("# %s", vim.bo[buf].commentstring, "the option is the caller's business, not the watcher's")
end

T["get() falls back to a range request until the watcher has a result"] = function()
	local client = H.fake_client({
		["kakehashi/captures/range"] = result_with({
			{
				patternIndex = 0,
				language = "lua",
				captures = { capture(range(10, 0, 20, 0), { commentstring = "-- %s" }) },
			},
		}),
	})
	local buf = H.scratch_buf()
	local commentstring = require("kakehashi.extra.commentstring")

	commentstring.watch({ client = client, bufnr = buf })
	H.eq("-- %s", commentstring.get({ client = client, bufnr = buf, range = range(12, 0, 12, 0) }))
	H.eq(1, #client.calls)
	H.eq("kakehashi/captures/range", client.calls[1].method)
end

T["watch() without bufnr serves get() for every buffer of the client"] = function()
	local client = H.fake_client({
		["kakehashi/captures/full"] = full_result_with({
			{
				patternIndex = 0,
				language = "lua",
				captures = { capture(range(0, 0, 50, 0), { commentstring = "-- %s" }) },
			},
		}),
		["kakehashi/captures/range"] = result_with({}),
	})
	local buf1 = H.scratch_buf()
	local buf2 = H.scratch_buf()
	local commentstring = require("kakehashi.extra.commentstring")

	commentstring.watch({ client = client })
	H.fire_lsp_request(client, { type = "pending", bufnr = buf1, method = "textDocument/semanticTokens/full" })

	H.eq("-- %s", commentstring.get({ client = client, bufnr = buf1, range = range(5, 0, 5, 0) }))
	H.eq(1, #client.calls, "buf1 should be served from the watcher")

	H.eq(nil, commentstring.get({ client = client, bufnr = buf2, range = range(5, 0, 5, 0) }))
	H.eq(2, #client.calls, "buf2 has no watched result yet and should fall back")
	H.eq("kakehashi/captures/range", client.calls[2].method)
end

T["a watched null result answers nil without falling back"] = function()
	local client = H.fake_client({ ["kakehashi/captures/full"] = vim.NIL })
	local buf = H.scratch_buf()
	local commentstring = require("kakehashi.extra.commentstring")

	commentstring.watch({ client = client, bufnr = buf })
	H.fire_lsp_request(client, { type = "pending", bufnr = buf, method = "textDocument/semanticTokens/full" })

	H.eq(nil, commentstring.get({ client = client, bufnr = buf, range = range(0, 0, 0, 0) }))
	H.eq(1, #client.calls, "a known-null result needs no range request")
end

T["watch() with the same parameters returns the live autocmd"] = function()
	local commentstring = require("kakehashi.extra.commentstring")
	local client = H.fake_client({})
	local buf = H.scratch_buf()
	local params = { client = client, bufnr = buf }

	local autocmd = commentstring.watch(params)
	H.eq(autocmd, commentstring.watch(params), "same parameters should reuse the watcher")
	assert(commentstring.watch({ client = client }) ~= autocmd, "different parameters need their own watcher")

	vim.api.nvim_del_autocmd(autocmd)
	assert(commentstring.watch(params) ~= autocmd, "a deleted watcher should be recreated")
end

return T
