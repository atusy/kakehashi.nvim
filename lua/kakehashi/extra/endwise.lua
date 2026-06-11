-- The detection model — an opener capture the cursor must sit in, a "does
-- the construct really own its closing keyword" check based on indentation
-- and surrounding parse errors, and bare-opener patterns inside ERROR
-- nodes — is derived from nvim-treesitter-endwise, reimplemented over
-- kakehashi server captures with plain #set! metadata:
--
--   https://github.com/RRethy/nvim-treesitter-endwise (MIT license)

local util = require("kakehashi.lsp.util")

local M = {}

---@param a lsp.Position
---@param b lsp.Position
---@return boolean a is at or before b
local function pos_le(a, b)
	return a.line < b.line or (a.line == b.line and a.character <= b.character)
end

---@param a lsp.Position
---@param b lsp.Position
---@return boolean a is strictly before b
local function pos_lt(a, b)
	return not pos_le(b, a)
end

---Half-open containment, mirroring nvim-treesitter-endwise's point_in_range.
---@param range lsp.Range
---@param position lsp.Position
---@return boolean
local function contains_position(range, position)
	return pos_le(range.start, position) and pos_lt(position, range["end"])
end

---Tree nodes never partially overlap, so intersection means one contains
---the other — enough to ask "is this construct involved in the breakage?".
---@param a lsp.Range
---@param b lsp.Range
---@return boolean
local function intersects(a, b)
	return pos_le(a.start, b["end"]) and pos_le(b.start, a["end"])
end

---@param bufnr integer
---@param row integer 0-based
---@return string leading whitespace of the line
local function indent_of(bufnr, row)
	local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
	return line:match("^%s*")
end

---@param ranges lsp.Range[]
---@param range lsp.Range
---@return boolean
local function any_intersects(ranges, range)
	for _, r in ipairs(ranges) do
		if intersects(r, range) then
			return true
		end
	end
	return false
end

---The closing keyword to insert, mirroring nvim-treesitter-endwise's
---lacks_end without touching the tree:
---
---- a bare opener (an `(ERROR ...)` pattern captures no @endwise construct)
---  always lacks its end;
---- a MISSING node inside the construct (@endwise.missing) means the parser
---  itself says the end is absent — insert, whatever the construct looks
---  like (a one-line `if true; then` carries its missing `fi` on the
---  cursor's own row);
---- a construct whose last line is the position's line, or is indented like
---  its first line, plausibly owns its closing keyword — leave it alone;
---- otherwise the closing keyword probably belongs to an enclosing
---  construct (tree-sitter error recovery hands outer ends to inner
---  statements), but only when the construct is involved in a parse error
---  (@endwise.error) — an indent mismatch alone is just unusual formatting.
---@param bufnr integer
---@param result { matches: KakehashiMatch[] } | nil
---@param position lsp.Position
---@return string | nil
local function resolve(bufnr, result, position)
	---@type lsp.Range[], lsp.Range[]
	local errors, missings = {}, {}
	---@type { text: string, cursor: lsp.Range, node?: lsp.Range }[]
	local candidates = {}
	for _, match in ipairs(result and result.matches or {}) do
		local text = match.metadata and match.metadata.endwise
		local cursor, node
		for _, capture in ipairs(match.captures) do
			if capture.name == "endwise.error" then
				errors[#errors + 1] = capture.range
			elseif capture.name == "endwise.missing" then
				missings[#missings + 1] = capture.range
			elseif capture.name == "endwise.cursor" and contains_position(capture.range, position) then
				cursor = capture.range
			elseif capture.name == "endwise" then
				node = capture.range
			end
		end
		if type(text) == "string" and cursor then
			candidates[#candidates + 1] = { text = text, cursor = cursor, node = node }
		end
	end

	table.sort(candidates, function(a, b)
		return pos_lt(b.cursor.start, a.cursor.start) -- innermost opener first
	end)
	for _, candidate in ipairs(candidates) do
		if not candidate.node or any_intersects(missings, candidate.node) then
			return candidate.text
		end
		local end_row = candidate.node["end"].line
		local closed = end_row == position.line
			or indent_of(bufnr, candidate.node.start.line) == indent_of(bufnr, end_row)
		if not closed and any_intersects(errors, candidate.node) then
			return candidate.text
		end
	end
	return nil
end

---The closest non-blank at or before the cursor, like the upstream plugin
---probes from insert mode: pressing <CR> at the end of `if cond then|`
---should consult the `n` of then, not the whitespace under the cursor.
---@param offset_encoding string
---@return lsp.Position | nil nil when the buffer has no non-blank before the cursor
local function position_before_cursor(offset_encoding)
	local found = vim.fn.searchpos([[\S]], "nbcW")
	if found[1] == 0 then
		return nil
	end
	local line = vim.api.nvim_buf_get_lines(0, found[1] - 1, found[1], false)[1] or ""
	return {
		line = found[1] - 1,
		character = vim.str_utfindex(line, offset_encoding, found[2] - 1, false),
	}
end

---The closing keyword (`end`, `fi`, `endif`, ...) the construct at the
---position still needs, or nil when everything is closed — decided by
---`queries/<lang>/endwise.scm` on the kakehashi server (this plugin ships a
---set under queries/): patterns capture the opener as @endwise.cursor and
---the construct as @endwise, and state the keyword with `#set! endwise`.
---The position defaults to the closest non-blank at or before the cursor.
---@param opts? {
---  position?: lsp.Position,
---  client?: vim.lsp.Client,
---  bufnr?: integer,
---  injection?: boolean,
---  timeout_ms?: integer,
---} injection defaults to true
---@return string | nil
function M.get(opts)
	opts = opts or {}
	local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
	local client = opts.client or util.get_client(bufnr)
	local position = opts.position or position_before_cursor(client.offset_encoding or "utf-16")
	if not position then
		return nil
	end
	-- whole-document captures, not a range request: the evidence for a
	-- missing end (a zero-width MISSING node, an ERROR spanning the
	-- construct) rarely touches the cursor position itself
	local result = require("kakehashi.lsp.captures").get({
		kind = "endwise",
		client = client,
		bufnr = bufnr,
		injection = opts.injection ~= false,
		timeout_ms = opts.timeout_ms,
	})
	return resolve(bufnr, result, position)
end

---Make get() cheap: watching is simply captures.watch() on kind "endwise" —
---get()'s range request is then answered from one delta merged over the
---watcher's result instead of a server-side traversal per <CR>.
---@param opts? { client?: vim.lsp.Client, bufnr?: integer, injection?: boolean } injection defaults to true
---@return integer autocmd id from captures.watch; delete it to stop watching
function M.watch(opts)
	opts = opts or {}
	return require("kakehashi.lsp.captures").watch({
		kind = "endwise",
		client = opts.client,
		bufnr = opts.bufnr,
		injection = opts.injection ~= false,
	})
end

return M
