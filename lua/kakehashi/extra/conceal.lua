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

---@class KakehashiConcealApplier
---@field autocmd integer User KakehashiCapturesUpdate subscriber
---@field marked table<integer, true> buffers this applier has set marks in
---@field client vim.lsp.Client the client this applier follows
---@field bufnr? integer the single buffer it follows, nil for an all-buffer applier

---Live appliers by parameter identity, mirroring captures.watch(): toggling
---flips the one subscriber for those parameters on and off.
---@type table<string, KakehashiConcealApplier>
local appliers = {}

---Clear a buffer's orphaned conceal marks when the client leaves it: no more
---KakehashiCapturesUpdate events will arrive for it, so the marks would
---otherwise linger frozen. A buffer-specific applier is reaped with its
---buffer; an all-buffer one is reaped once its client serves nothing more.
---@param client_id integer
---@param bufnr integer
local function detach(client_id, bufnr)
	for key, applier in pairs(appliers) do
		if applier.client.id == client_id then
			if vim.api.nvim_buf_is_valid(bufnr) then
				vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
			end
			applier.marked[bufnr] = nil
			if util.reap_on_detach(applier.client, applier.bufnr, bufnr) then
				-- A stopping client detaches every buffer, but reap fires on the
				-- first: clear the marks of every other buffer now, or they stay
				-- frozen once the applier is gone and stops hearing detaches.
				for marked_bufnr in pairs(applier.marked) do
					if vim.api.nvim_buf_is_valid(marked_bufnr) then
						vim.api.nvim_buf_clear_namespace(marked_bufnr, ns, 0, -1)
					end
				end
				pcall(vim.api.nvim_del_autocmd, applier.autocmd)
				appliers[key] = nil
			end
		end
	end
end

-- One LspDetach autocmd drives every applier's teardown; installed lazily.
local detach_installed = false
local function ensure_detach_handler()
	if detach_installed then
		return
	end
	detach_installed = true
	vim.api.nvim_create_autocmd("LspDetach", {
		callback = function(ev)
			detach(ev.data.client_id, ev.buf)
		end,
	})
end

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

---Toggle concealing text the way `highlights.scm` directs (`#set! conceal`),
---driven by the kakehashi server instead of a client-side Tree-sitter parse:
---a captures.watch() on kind "highlights" keeps the captures fresh, and every
---KakehashiCapturesUpdate re-derives the conceal extmarks for that buffer.
---Toggling off removes the subscriber and its marks, but leaves the watcher
---running: captures.watch() shares watchers by parameters, so others may
---depend on it, and a later re-enable picks its live result up instantly.
---Conceal only shows once 'conceallevel' is set; that is left to the user.
---@param opts? { client?: vim.lsp.Client, bufnr?: integer, injection?: boolean } injection defaults to true: conceal usually lives in injected layers
---@return boolean enabled whether this call turned concealing on
function M.toggle(opts)
	opts = opts or {}
	local injection = opts.injection ~= false
	local client = opts.client or util.get_client(opts.bufnr or vim.api.nvim_get_current_buf())
	local offset_encoding = client.offset_encoding or "utf-16"

	local key = ("%d/%s/%s"):format(client.id, opts.bufnr or "*", tostring(injection))
	local existing = appliers[key]
	if existing and applier_alive(existing.autocmd) then
		vim.api.nvim_del_autocmd(existing.autocmd)
		appliers[key] = nil
		for bufnr in pairs(existing.marked) do
			if vim.api.nvim_buf_is_valid(bufnr) then
				vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
			end
		end
		return false
	end

	local marked = {}
	local applier = vim.api.nvim_create_autocmd("User", {
		pattern = "KakehashiCapturesUpdate",
		callback = function(ev)
			if ev.data.kind ~= "highlights" or ev.data.injection ~= injection then
				return
			end
			if opts.bufnr and ev.data.bufnr ~= opts.bufnr then
				return
			end
			marked[ev.data.bufnr] = true
			apply_conceal(ev.data.bufnr, ev.data.result, offset_encoding)
		end,
	})
	appliers[key] = { autocmd = applier, marked = marked, client = client, bufnr = opts.bufnr }
	ensure_detach_handler()

	-- after the applier, so it hears the watcher's seed or replay right away
	require("kakehashi.lsp.captures").watch({
		kind = "highlights",
		client = client,
		bufnr = opts.bufnr,
		injection = injection,
	})
	return true
end

return M
