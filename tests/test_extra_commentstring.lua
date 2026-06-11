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

T["watch() keeps 'commentstring' in sync with the cursor context"] = function()
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
	local lines = {}
	for i = 1, 40 do
		lines[i] = "L" .. i
	end
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_win_set_buf(0, buf)
	vim.bo[buf].commentstring = "# %s"
	vim.api.nvim_win_set_cursor(0, { 12, 0 })

	require("kakehashi.extra.commentstring").watch({ client = client, bufnr = buf })

	H.eq("kakehashi/captures/range", client.calls[1].method)
	H.eq("commentstring", client.calls[1].params.kind)
	H.eq(range(11, 0, 11, 0), client.calls[1].params.range)
	H.eq("-- %s", vim.bo[buf].commentstring, "watch() should update on creation, before any cursor event")

	-- outside every capture the original option value comes back
	vim.api.nvim_win_set_cursor(0, { 30, 0 })
	vim.api.nvim_exec_autocmds("CursorMoved", {})
	H.eq("# %s", vim.bo[buf].commentstring)

	-- a watcher pinned to a buffer ignores events from other buffers
	local calls = #client.calls
	vim.api.nvim_win_set_buf(0, H.scratch_buf())
	vim.api.nvim_exec_autocmds("CursorMoved", {})
	H.eq(calls, #client.calls)
end

T["watch() without bufnr follows the buffers the client is attached to"] = function()
	local client = H.fake_client({
		["kakehashi/captures/range"] = result_with({
			{
				patternIndex = 0,
				language = "lua",
				captures = { capture(range(0, 0, 50, 0), { commentstring = "-- %s" }) },
			},
		}),
	})
	local attached_buf = H.scratch_buf()
	local other_buf = H.scratch_buf()
	client.attached_buffers = { [attached_buf] = true }
	vim.api.nvim_win_set_buf(0, other_buf)

	require("kakehashi.extra.commentstring").watch({ client = client })
	H.eq({}, client.calls, "buffers the client does not serve should be left alone")

	vim.api.nvim_win_set_buf(0, attached_buf)
	vim.api.nvim_exec_autocmds("CursorMoved", {})
	assert(#client.calls > 0, "expected a request for the attached buffer")
	for _, call in ipairs(client.calls) do
		H.eq(vim.uri_from_bufnr(attached_buf), call.params.textDocument.uri)
	end
	H.eq("-- %s", vim.bo[attached_buf].commentstring)
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
