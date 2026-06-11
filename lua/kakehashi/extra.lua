local util = require("kakehashi.lsp.util")

local M = {}

local ns = vim.api.nvim_create_namespace("kakehashi.extra.conceal")

---@param bufnr integer
---@param position { line: integer, character: integer }
---@param offset_encoding string
---@return integer row 0-based
---@return integer col byte index
local function to_byte_pos(bufnr, position, offset_encoding)
	local line = vim.api.nvim_buf_get_lines(bufnr, position.line, position.line + 1, false)[1] or ""
	return position.line, vim.str_byteindex(line, offset_encoding, position.character, false)
end

---Re-derive the buffer's conceal extmarks from a captures result, honoring
---the same metadata the Tree-sitter highlighter does: capture-level conceal
---wins over the match-level #set! that applies to every capture of a pattern.
---@param bufnr integer
---@param result KakehashiCapturesResult | nil
---@param offset_encoding string
local function apply_conceal(bufnr, result, offset_encoding)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end
	vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
	for _, match in ipairs(result and result.matches or {}) do
		local match_conceal = match.metadata and match.metadata.conceal
		for _, capture in ipairs(match.captures) do
			local conceal = capture.metadata and capture.metadata.conceal
			if conceal == nil then
				conceal = match_conceal
			end
			if type(conceal) == "string" then
				local row, col = to_byte_pos(bufnr, capture.range.start, offset_encoding)
				local end_row, end_col = to_byte_pos(bufnr, capture.range["end"], offset_encoding)
				vim.api.nvim_buf_set_extmark(bufnr, ns, row, col, {
					end_row = end_row,
					end_col = end_col,
					conceal = conceal,
				})
			end
		end
	end
end

---Live appliers by parameter identity, mirroring captures.watch(): repeated
---conceal() calls share one subscriber instead of re-deriving marks N times.
---@type table<string, integer>
local appliers = {}

---@param autocmd integer
---@return boolean whether the autocmd has not been deleted
local function applier_alive(autocmd)
	local subscribers = vim.api.nvim_get_autocmds({ event = "User", pattern = "KakehashiCapturesUpdate" })
	for _, au in ipairs(subscribers) do
		if au.id == autocmd then
			return true
		end
	end
	return false
end

---Conceal text the way `highlights.scm` directs (`#set! conceal`), driven by
---the kakehashi server instead of a client-side Tree-sitter parse: a
---captures.watch() on kind "highlights" keeps the captures fresh, and every
---KakehashiCapturesUpdate re-derives the conceal extmarks for that buffer.
---Conceal only shows once 'conceallevel' is set; that is left to the user.
---@param opts? { client?: vim.lsp.Client, bufnr?: integer, injection?: boolean } injection defaults to true: conceal usually lives in injected layers
---@return integer watcher LspRequest autocmd id from captures.watch
---@return integer applier User KakehashiCapturesUpdate autocmd id
function M.conceal(opts)
	opts = opts or {}
	local injection = opts.injection ~= false
	local client = opts.client or util.get_client(opts.bufnr or vim.api.nvim_get_current_buf())
	local offset_encoding = client.offset_encoding or "utf-16"

	local watcher = require("kakehashi.lsp.captures").watch({
		kind = "highlights",
		client = client,
		bufnr = opts.bufnr,
		injection = injection,
	})

	local key = ("%d/%s/%s"):format(client.id, opts.bufnr or "*", tostring(injection))
	local existing = appliers[key]
	if existing and applier_alive(existing) then
		return watcher, existing
	end

	local applier = vim.api.nvim_create_autocmd("User", {
		pattern = "KakehashiCapturesUpdate",
		callback = function(ev)
			if ev.data.kind ~= "highlights" or ev.data.injection ~= injection then
				return
			end
			if opts.bufnr and ev.data.bufnr ~= opts.bufnr then
				return
			end
			apply_conceal(ev.data.bufnr, ev.data.result, offset_encoding)
		end,
	})
	appliers[key] = applier
	return watcher, applier
end

return M
