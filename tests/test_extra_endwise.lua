local H = dofile("tests/helpers.lua")

local T = {}

local function range(start_line, start_char, end_line, end_char)
	return {
		start = { line = start_line, character = start_char },
		["end"] = { line = end_line, character = end_char },
	}
end

local function capture(name, rng)
	return { name = name, node = { id = name, kind = "x" }, range = rng }
end

local function result_with(matches)
	return { matches = matches, skipped = {} }
end

---An if-like construct: opener token to put the cursor in, the whole node,
---and the match-level end text.
local function construct(cursor, node, text)
	return {
		patternIndex = 0,
		language = "lua",
		captures = { capture("endwise.cursor", cursor), capture("endwise", node) },
		metadata = { endwise = text },
	}
end

local function error_match(rng)
	return { patternIndex = 9, language = "lua", captures = { capture("endwise.error", rng) } }
end

---A buffer like:
---  function f()
---    if cond then
---  end
local function broken_buf()
	local buf = H.scratch_buf()
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "function f()", "  if cond then", "end" })
	return buf
end

T["get() inserts for an opener inside an ERROR (no construct to check)"] = function()
	local client = H.fake_client({
		["kakehashi/captures/full"] = result_with({
			{
				patternIndex = 1,
				language = "lua",
				captures = { capture("endwise.cursor", range(0, 9, 0, 12)) },
				metadata = { endwise = "end" },
			},
		}),
	})
	local buf = broken_buf()
	local position = { line = 0, character = 10 }

	local text = require("kakehashi.extra.endwise").get({ client = client, bufnr = buf, position = position })

	H.eq(1, #client.calls)
	-- whole-document captures: error/missing evidence rarely touches the cursor
	H.eq("kakehashi/captures/full", client.calls[1].method)
	H.eq({
		textDocument = { uri = vim.uri_from_bufnr(buf) },
		kind = "endwise",
		injection = true,
	}, client.calls[1].params)
	H.eq("end", text)
end

T["get() inserts when the construct stole an outer end inside a broken region"] = function()
	-- the if on line 1 adopted the function's end on line 2: indents differ
	local client = H.fake_client({
		["kakehashi/captures/full"] = result_with({
			construct(range(1, 12, 1, 16), range(1, 2, 2, 3), "end"),
			error_match(range(0, 0, 2, 3)),
		}),
	})
	local text = require("kakehashi.extra.endwise").get({
		client = client,
		bufnr = broken_buf(),
		position = { line = 1, character = 13 }, -- inside "then"
	})
	H.eq("end", text)
end

T["get() leaves a suspicious construct alone outside any broken region"] = function()
	local client = H.fake_client({
		["kakehashi/captures/full"] = result_with({
			construct(range(1, 12, 1, 16), range(1, 2, 2, 3), "end"),
		}),
	})
	H.eq(
		nil,
		require("kakehashi.extra.endwise").get({
			client = client,
			bufnr = broken_buf(),
			position = { line = 1, character = 13 },
		}),
		"an indent mismatch alone is just unusual formatting, not a missing end"
	)
end

T["get() treats matching indentation as a closed construct"] = function()
	local buf = H.scratch_buf()
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "if cond then", "  x()", "end" })
	local client = H.fake_client({
		["kakehashi/captures/full"] = result_with({
			construct(range(0, 8, 0, 12), range(0, 0, 2, 3), "end"),
			error_match(range(0, 0, 2, 3)), -- even inside a broken region
		}),
	})
	H.eq(
		nil,
		require("kakehashi.extra.endwise").get({
			client = client,
			bufnr = buf,
			position = { line = 0, character = 9 },
		})
	)
end

T["get() treats an end on the cursor row as closed"] = function()
	local buf = H.scratch_buf()
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "  if cond then x() end" })
	local client = H.fake_client({
		["kakehashi/captures/full"] = result_with({
			construct(range(0, 10, 0, 14), range(0, 2, 0, 22), "end"),
			error_match(range(0, 0, 0, 22)),
		}),
	})
	H.eq(
		nil,
		require("kakehashi.extra.endwise").get({
			client = client,
			bufnr = buf,
			position = { line = 0, character = 11 },
		})
	)
end

T["a MISSING end overrides every closed-looking heuristic"] = function()
	-- bash `if true; then` parses as a one-line if_statement whose "fi" is a
	-- zero-width MISSING node at its end: same row as the cursor, same
	-- indentation — but the parser itself says the end is absent
	local buf = H.scratch_buf()
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "if true; then" })
	local client = H.fake_client({
		["kakehashi/captures/full"] = result_with({
			construct(range(0, 9, 0, 13), range(0, 0, 0, 13), "fi"),
			{
				patternIndex = 9,
				language = "bash",
				captures = { capture("endwise.missing", range(0, 13, 0, 13)) },
			},
		}),
	})
	H.eq(
		"fi",
		require("kakehashi.extra.endwise").get({
			client = client,
			bufnr = buf,
			position = { line = 0, character = 10 },
		})
	)
end

T["the innermost opener wins"] = function()
	local buf = broken_buf()
	local client = H.fake_client({
		["kakehashi/captures/full"] = result_with({
			{
				patternIndex = 1,
				language = "lua",
				captures = { capture("endwise.cursor", range(0, 0, 2, 3)) },
				metadata = { endwise = "outer" },
			},
			{
				patternIndex = 1,
				language = "lua",
				captures = { capture("endwise.cursor", range(1, 12, 1, 16)) },
				metadata = { endwise = "inner" },
			},
		}),
	})
	H.eq(
		"inner",
		require("kakehashi.extra.endwise").get({
			client = client,
			bufnr = buf,
			position = { line = 1, character = 13 },
		})
	)
end

T["get() defaults to the closest non-blank at or before the cursor"] = function()
	local client = H.fake_client({
		["kakehashi/captures/full"] = result_with({
			-- only an opener containing the final n of "then" (utf-16
			-- character 10; byte column 12) can produce this answer
			{
				patternIndex = 1,
				language = "lua",
				captures = { capture("endwise.cursor", range(0, 7, 0, 11)) },
				metadata = { endwise = "end" },
			},
		}),
	})
	local buf = H.scratch_buf()
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "  if あ then", "" })
	vim.api.nvim_win_set_buf(0, buf)
	-- cursor at the start of the empty second line
	vim.api.nvim_win_set_cursor(0, { 2, 0 })

	H.eq("end", require("kakehashi.extra.endwise").get({ client = client, bufnr = buf }))
end

T["get() returns nil on a null result"] = function()
	local client = H.fake_client({ ["kakehashi/captures/full"] = vim.NIL })
	H.eq(
		nil,
		require("kakehashi.extra.endwise").get({
			client = client,
			bufnr = H.scratch_buf(),
			position = { line = 0, character = 0 },
		})
	)
end

T["watch() is just the captures watcher on kind endwise"] = function()
	local client = H.fake_client({})
	local buf = H.scratch_buf()
	local endwise = require("kakehashi.extra.endwise")

	local autocmd = endwise.watch({ client = client, bufnr = buf })
	H.eq(
		autocmd,
		require("kakehashi.lsp.captures").watch({
			kind = "endwise",
			client = client,
			bufnr = buf,
			injection = true,
		})
	)
	H.eq(autocmd, endwise.watch({ client = client, bufnr = buf }))
end

return T
