local H = dofile("tests/helpers.lua")

local T = {}

local function range(start_line, start_char, end_line, end_char)
	return {
		start = { line = start_line, character = start_char },
		["end"] = { line = end_line, character = end_char },
	}
end

local function context_capture(name, rng)
	return { name = name, node = { id = name, kind = "x" }, range = rng }
end

local function result_with(captures)
	return {
		resultId = "r1",
		matches = { { patternIndex = 0, language = "lua", captures = captures } },
		skipped = {},
	}
end

local function floats()
	return vim.tbl_filter(function(win)
		return vim.api.nvim_win_get_config(win).relative ~= ""
	end, vim.api.nvim_list_wins())
end

local function float_lines(win)
	return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
end

---A 40-line buffer ("L1".."L40") shown in the current window.
local function buf_in_current_win()
	local buf = H.scratch_buf()
	local lines = {}
	for i = 1, 40 do
		lines[i] = "L" .. i
	end
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_win_set_buf(0, buf)
	return buf
end

T["context.toggle() floats headers of contexts scrolled off above the window"] = function()
	local client = H.fake_client({
		["kakehashi/captures/full"] = result_with({
			context_capture("context", range(0, 0, 29, 3)),
			-- refinement captures do not define contexts of their own
			context_capture("context.start", range(2, 0, 2, 5)),
		}),
	})
	local buf = buf_in_current_win()
	vim.fn.winrestview({ topline = 6, lnum = 12, col = 0 })
	local toggle = require("kakehashi.extra.context").toggle
	local pending = { type = "pending", bufnr = buf, method = "textDocument/semanticTokens/full" }

	H.eq(true, toggle({ client = client, bufnr = buf }))
	H.fire_lsp_request(client, pending)

	H.eq("context", client.calls[1].params.kind)
	H.eq(true, client.calls[1].params.injection, "context queries may live in injected layers by default")
	local fs = floats()
	H.eq(1, #fs)
	H.eq({ "L1" }, float_lines(fs[1]))
	local config = vim.api.nvim_win_get_config(fs[1])
	H.eq("win", config.relative)
	H.eq(0, config.row)
	H.eq(1, config.height)

	H.eq(false, toggle({ client = client, bufnr = buf }), "second toggle should turn context off")
	H.eq({}, floats(), "toggling off should close the context window")
	H.fire_lsp_request(client, pending)
	H.eq({}, floats(), "a disabled context applier must not render")
end

T["context.toggle() stacks nested contexts and never covers the cursor line"] = function()
	local client = H.fake_client({
		["kakehashi/captures/full"] = result_with({
			context_capture("context", range(0, 0, 34, 3)),
			context_capture("context", range(4, 2, 30, 5)),
		}),
		["kakehashi/captures/full/delta"] = { resultId = "r2", edits = {} },
	})
	local buf = buf_in_current_win()
	local toggle = require("kakehashi.extra.context").toggle
	local pending = { type = "pending", bufnr = buf, method = "textDocument/semanticTokens/full" }

	vim.fn.winrestview({ topline = 6, lnum = 12, col = 0 })
	H.eq(true, toggle({ client = client, bufnr = buf }))
	H.fire_lsp_request(client, pending)
	H.eq({ "L1", "L5" }, float_lines(floats()[1]), "outer context should stack above the inner one")

	-- with the cursor just below the topline there is room for one header only
	vim.fn.winrestview({ topline = 6, lnum = 7, col = 0 })
	H.fire_lsp_request(client, pending)
	H.eq({ "L1" }, float_lines(floats()[1]))

	-- back at the top no header has scrolled off
	vim.fn.winrestview({ topline = 1, lnum = 3, col = 0 })
	H.fire_lsp_request(client, pending)
	H.eq({}, floats(), "no context should show when its header is visible")

	toggle({ client = client, bufnr = buf })
end

T["context.toggle() accounts for lines its own headers cover"] = function()
	local client = H.fake_client({
		["kakehashi/captures/full"] = result_with({
			context_capture("context", range(0, 0, 34, 3)),
			-- starts on the topline itself: visible at first, but covered
			-- (and thus a context) once the outer header is pinned above it
			context_capture("context", range(5, 2, 30, 5)),
		}),
	})
	local buf = buf_in_current_win()
	local toggle = require("kakehashi.extra.context").toggle

	vim.fn.winrestview({ topline = 6, lnum = 12, col = 0 })
	H.eq(true, toggle({ client = client, bufnr = buf }))
	H.fire_lsp_request(client, { type = "pending", bufnr = buf, method = "textDocument/semanticTokens/full" })
	H.eq({ "L1", "L6" }, float_lines(floats()[1]))

	toggle({ client = client, bufnr = buf })
end

T["context.toggle() honors max_lines"] = function()
	local client = H.fake_client({
		["kakehashi/captures/full"] = result_with({
			context_capture("context", range(0, 0, 34, 3)),
			context_capture("context", range(4, 2, 30, 5)),
		}),
	})
	local buf = buf_in_current_win()
	local toggle = require("kakehashi.extra.context").toggle

	vim.fn.winrestview({ topline = 6, lnum = 12, col = 0 })
	H.eq(true, toggle({ client = client, bufnr = buf, max_lines = 1 }))
	H.fire_lsp_request(client, { type = "pending", bufnr = buf, method = "textDocument/semanticTokens/full" })
	H.eq({ "L1" }, float_lines(floats()[1]), "max_lines should cap the stack at the outermost context")

	toggle({ client = client, bufnr = buf, max_lines = 1 })
end

T["context.toggle() tracks each parameter set independently"] = function()
	local toggle = require("kakehashi.extra.context").toggle
	local client = H.fake_client({})
	local buf = H.scratch_buf()

	H.eq(true, toggle({ client = client, bufnr = buf }))
	H.eq(true, toggle({ client = client }), "an all-buffer toggle is not the buffer-pinned one")
	H.eq(false, toggle({ client = client }))
	H.eq(false, toggle({ client = client, bufnr = buf }), "the buffer-pinned toggle should still be on")
end

return T
