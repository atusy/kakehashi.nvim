local util = require("kakehashi.lsp.util")

local M = {}

---@param a lsp.Position
---@param b lsp.Position
---@return boolean a is at or before b
local function pos_le(a, b)
	return a.line < b.line or (a.line == b.line and a.character <= b.character)
end

---@param outer lsp.Range
---@param inner lsp.Range
---@return boolean
local function contains(outer, inner)
	return pos_le(outer.start, inner.start) and pos_le(inner["end"], outer["end"])
end

---The cursor as a zero-width range in the client's offset encoding.
---@param offset_encoding string
---@return lsp.Range
local function cursor_range(offset_encoding)
	local row, col = unpack(vim.api.nvim_win_get_cursor(0))
	local line = vim.api.nvim_get_current_line()
	local position = {
		line = row - 1,
		character = vim.str_utfindex(line, offset_encoding, math.min(col, #line), false),
	}
	return { start = position, ["end"] = position }
end

---The commentstring of the innermost capture containing the range: language
---layers and nodes nest, so the capture contained by every other containing
---capture is the most specific context (e.g. a lua chunk injected in
---markdown, or a jsx_element within a javascript program).
---@param result { matches: KakehashiMatch[] } | nil
---@param range lsp.Range
---@return string | nil
local function resolve(result, range)
	local best ---@type string | nil
	local best_range ---@type lsp.Range | nil
	for _, match in ipairs(result and result.matches or {}) do
		local match_commentstring = match.metadata and match.metadata.commentstring
		for _, capture in ipairs(match.captures) do
			local commentstring = capture.metadata and capture.metadata.commentstring
			if commentstring == nil then
				commentstring = match_commentstring
			end
			if type(commentstring) == "string" and contains(capture.range, range) then
				if best_range == nil or contains(best_range, capture.range) then
					best, best_range = commentstring, capture.range
				end
			end
		end
	end
	return best
end

---Context-aware 'commentstring' the way nvim-ts-context-commentstring
---computes it, but decided by `queries/<lang>/commentstring.scm` on the
---kakehashi server (this plugin ships a starter set under queries/; put the
---plugin directory on the server's searchPaths): each query captures the
---nodes a commentstring applies to and states the value with
---`#set! commentstring "..."`. The range narrows the decision client-side —
---pass the selection about to be commented; it defaults to the cursor
---position.
---
---The request is a synchronous `kakehashi/captures/full`; with a live
---watch() it shrinks to a delta merged over the watcher's result, so the
---answer always reflects the current document.
---@param opts? {
---  range?: lsp.Range,
---  client?: vim.lsp.Client,
---  bufnr?: integer,
---  injection?: boolean,
---  timeout_ms?: integer,
---} injection defaults to true: the context usually is an injected layer
---@return string | nil commentstring nil when no capture covers the range
function M.get(opts)
	opts = opts or {}
	local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
	local client = opts.client or util.get_client(bufnr)
	local range = opts.range or cursor_range(client.offset_encoding or "utf-16")
	local result = require("kakehashi.lsp.captures").get({
		kind = "commentstring",
		client = client,
		bufnr = bufnr,
		injection = opts.injection ~= false,
		timeout_ms = opts.timeout_ms,
	})
	return resolve(result, range)
end

---Rows srow..erow (1-based, inclusive) trimmed to the first and last
---non-blank characters, so surrounding indentation does not push the range
---out of the capture that actually contains the code.
---@param bufnr integer
---@param srow integer
---@param erow integer
---@param offset_encoding string
---@return lsp.Range
local function trimmed_line_range(bufnr, srow, erow, offset_encoding)
	local first = vim.api.nvim_buf_get_lines(bufnr, srow - 1, srow, false)[1] or ""
	local last = srow == erow and first or vim.api.nvim_buf_get_lines(bufnr, erow - 1, erow, false)[1] or ""
	local start_col = (first:find("%S") or 1) - 1
	local end_col = #(last:gsub("%s+$", ""))
	return {
		start = { line = srow - 1, character = vim.str_utfindex(first, offset_encoding, start_col, false) },
		["end"] = { line = erow - 1, character = vim.str_utfindex(last, offset_encoding, end_col, false) },
	}
end

local CTYPE_BLOCKWISE = 2 -- Comment.utils.ctype.blockwise

---A Comment.nvim pre_hook resolving the commentstring through the kakehashi
---server:
---
---  require("Comment").setup({
---    pre_hook = require("kakehashi.extra.commentstring").create_pre_hook(),
---  })
---
---The hook consults the rows about to be commented (indentation excluded),
---so a linewise toggle spanning out of e.g. a jsx_element falls back to the
---surrounding context. Blockwise operations only accept a value with a
---closing side ("{/* %s */}" qualifies, "-- %s" does not); anything else —
---including buffers without a kakehashi client — returns nil so Comment.nvim
---falls back to its own tables.
---@param opts? { client?: vim.lsp.Client, bufnr?: integer, injection?: boolean, timeout_ms?: integer } forwarded to get()
---@return fun(ctx: { ctype: integer, range: { srow: integer, erow: integer } }): string | nil
function M.create_pre_hook(opts)
	opts = opts or {}
	return function(ctx)
		local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
		local ok, client = pcall(function()
			return opts.client or util.get_client(bufnr)
		end)
		if not ok then
			return nil
		end
		local value = M.get({
			client = client,
			bufnr = bufnr,
			injection = opts.injection,
			timeout_ms = opts.timeout_ms,
			range = trimmed_line_range(bufnr, ctx.range.srow, ctx.range.erow, client.offset_encoding or "utf-16"),
		})
		if value and ctx.ctype == CTYPE_BLOCKWISE and not value:find("%%s%s*%S") then
			return nil
		end
		return value
	end
end

---Make get() cheap: watching is simply captures.watch() on kind
---"commentstring" — get() then cooperates with that watcher, continuing its
---delta lineage instead of running a full traversal per call, and hands its
---merged result back as the new lineage. The 'commentstring' option is never
---touched; applying get()'s value stays the caller's business.
---@param opts? { client?: vim.lsp.Client, bufnr?: integer, injection?: boolean } injection defaults to true
---@return integer autocmd id from captures.watch; delete it to stop watching
function M.watch(opts)
	opts = opts or {}
	return require("kakehashi.lsp.captures").watch({
		kind = "commentstring",
		client = opts.client,
		bufnr = opts.bufnr,
		injection = opts.injection ~= false,
	})
end

return M
