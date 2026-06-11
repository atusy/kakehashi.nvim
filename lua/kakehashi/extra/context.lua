-- The context model here — pinning the headers of @context captures that
-- scrolled off above the topline, recomputing against the rows the pinned
-- headers themselves cover, never covering the cursor line, and the float
-- placement (win-relative at row 0, past 'textoff') — is derived from
-- nvim-treesitter-context, reimplemented over kakehashi server captures:
--
--   https://github.com/nvim-treesitter/nvim-treesitter-context
--
-- nvim-treesitter-context is distributed under the MIT license:
--
--   Copyright * romgrk
--
--   Permission is hereby granted, free of charge, to any person obtaining a
--   copy of this software and associated documentation files (the
--   "Software"), to deal in the Software without restriction, including
--   without limitation the rights to use, copy, modify, merge, publish,
--   distribute, sublicense, and/or sell copies of the Software, and to
--   permit persons to whom the Software is furnished to do so, subject to
--   the following conditions:
--
--   The above copyright notice and this permission notice shall be included
--   in all copies or substantial portions of the Software.
--
--   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
--   OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
--   MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
--   IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
--   CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
--   TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
--   SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

local util = require("kakehashi.lsp.util")

local M = {}

vim.api.nvim_set_hl(0, "KakehashiContext", { link = "NormalFloat", default = true })

---@param range lsp.Range
---@return integer last 0-based line the range still touches
local function last_line(range)
	-- an end at character 0 stops before that line, LSP ranges being end-exclusive
	return range["end"].character == 0 and range["end"].line - 1 or range["end"].line
end

---Ranges of @context captures: only they define contexts; the refinement
---captures of nvim-treesitter-context queries (context.start/end/final)
---adjust what that plugin displays and are irrelevant to the header line.
---@param result KakehashiCapturesResult | nil
---@return lsp.Range[]
local function context_ranges(result)
	local ranges = {}
	for _, match in ipairs(result and result.matches or {}) do
		for _, capture in ipairs(match.captures) do
			if capture.name == "context" then
				ranges[#ranges + 1] = capture.range
			end
		end
	end
	return ranges
end

---Header rows to pin at the top of a window, outermost context first: the
---contexts containing the first visible row whose own header has scrolled
---off. Every pinned header covers one more screen line, so the first row the
---user actually sees moves down; recompute against that row until the answer
---stops moving (mirroring nvim-treesitter-context's fixpoint loop).
---@param ranges lsp.Range[] @context capture ranges
---@param top_row integer 0-based buffer row at the window top
---@param max_lines integer
---@return integer[] rows 0-based buffer rows whose lines to show
local function context_rows(ranges, top_row, max_lines)
	if max_lines < 1 then
		return {}
	end
	local sorted = vim.list_slice(ranges)
	table.sort(sorted, function(a, b)
		if a.start.line ~= b.start.line then
			return a.start.line < b.start.line
		end
		return last_line(a) > last_line(b)
	end)
	local rows = {}
	for offset = 0, max_lines do
		local target = top_row + offset
		rows = {}
		for _, range in ipairs(sorted) do
			if #rows >= max_lines then
				break
			end
			local covered = top_row + #rows -- first row still visible below the headers
			if range.start.line < covered and range.start.line <= target and target <= last_line(range) then
				if rows[#rows] ~= range.start.line then
					rows[#rows + 1] = range.start.line
				end
			end
		end
		if target >= top_row + #rows then
			break
		end
	end
	return rows
end

---@class KakehashiContextState
---@field applier integer User KakehashiCapturesUpdate subscriber
---@field autocmds integer[] window-event autocmds driving re-renders
---@field latest table<integer, lsp.Range[]> @context ranges per buffer
---@field floats table<integer, { win: integer, buf: integer }> context float per source window

---Live states by parameter identity, mirroring extra.conceal: toggling flips
---the one applier for those parameters on and off.
---@type table<string, KakehashiContextState>
local states = {}

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

---@param state KakehashiContextState
---@param win integer source window
local function close_float(state, win)
	local float = state.floats[win]
	state.floats[win] = nil
	if float and vim.api.nvim_win_is_valid(float.win) then
		vim.api.nvim_win_close(float.win, true)
	end
end

---@param state KakehashiContextState
---@param win integer source window
---@param max_lines? integer
local function render(state, win, max_lines)
	local bufnr = vim.api.nvim_win_get_buf(win)
	local ranges = state.latest[bufnr]
	if not ranges then
		return close_float(state, win)
	end

	local view = vim.api.nvim_win_call(win, vim.fn.winsaveview)
	local top_row = view.topline - 1
	-- the context window must never cover the cursor line
	local below_cursor = view.lnum - view.topline
	local rows = context_rows(ranges, top_row, math.min(max_lines or math.huge, below_cursor))
	if #rows == 0 then
		return close_float(state, win)
	end

	local lines = vim.tbl_map(function(row)
		return vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
	end, rows)
	local textoff = vim.fn.getwininfo(win)[1].textoff
	local win_config = {
		relative = "win",
		win = win,
		row = 0,
		col = textoff,
		width = math.max(1, vim.api.nvim_win_get_width(win) - textoff),
		height = #rows,
	}

	local float = state.floats[win]
	if float and vim.api.nvim_win_is_valid(float.win) then
		vim.api.nvim_win_set_config(float.win, win_config)
	else
		local buf = vim.api.nvim_create_buf(false, true)
		vim.bo[buf].bufhidden = "wipe"
		win_config.focusable = false
		win_config.style = "minimal"
		win_config.noautocmd = true
		win_config.zindex = 20
		local float_win = vim.api.nvim_open_win(buf, false, win_config)
		vim.wo[float_win].winhl = "NormalFloat:KakehashiContext"
		float = { win = float_win, buf = buf }
		state.floats[win] = float
	end
	vim.api.nvim_buf_set_lines(float.buf, 0, -1, false, lines)
end

---Toggle sticky context headers for the current window, like
---nvim-treesitter-context but driven by the kakehashi server: a
---captures.watch() on kind "context" keeps the @context captures of the
---user's `queries/<lang>/context.scm` fresh, and window events re-derive
---which headers have scrolled off above the topline. Toggling off removes
---the subscriber and its floats but leaves the watcher running, mirroring
---extra.conceal.
---@param opts? { client?: vim.lsp.Client, bufnr?: integer, injection?: boolean, max_lines?: integer } injection defaults to true
---@return boolean enabled whether this call turned context on
function M.toggle(opts)
	opts = opts or {}
	local injection = opts.injection ~= false
	local client = opts.client or util.get_client(opts.bufnr or vim.api.nvim_get_current_buf())

	local key = ("%d/%s/%s"):format(client.id, opts.bufnr or "*", tostring(injection))
	local existing = states[key]
	if existing and applier_alive(existing.applier) then
		vim.api.nvim_del_autocmd(existing.applier)
		for _, autocmd in ipairs(existing.autocmds) do
			pcall(vim.api.nvim_del_autocmd, autocmd)
		end
		for win in pairs(existing.floats) do
			close_float(existing, win)
		end
		states[key] = nil
		return false
	end

	require("kakehashi.lsp.captures").watch({
		kind = "context",
		client = client,
		bufnr = opts.bufnr,
		injection = injection,
	})

	---@type KakehashiContextState
	local state = { applier = 0, autocmds = {}, latest = {}, floats = {} }

	local function update_current_win()
		local win = vim.api.nvim_get_current_win()
		if opts.bufnr and vim.api.nvim_win_get_buf(win) ~= opts.bufnr then
			return close_float(state, win)
		end
		render(state, win, opts.max_lines)
	end

	state.applier = vim.api.nvim_create_autocmd("User", {
		pattern = "KakehashiCapturesUpdate",
		callback = function(ev)
			if ev.data.kind ~= "context" or ev.data.injection ~= injection then
				return
			end
			if opts.bufnr and ev.data.bufnr ~= opts.bufnr then
				return
			end
			state.latest[ev.data.bufnr] = context_ranges(ev.data.result)
			update_current_win()
		end,
	})
	state.autocmds = {
		vim.api.nvim_create_autocmd({ "WinScrolled", "CursorMoved", "BufEnter", "WinEnter", "VimResized" }, {
			callback = update_current_win,
		}),
		vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
			callback = function()
				close_float(state, vim.api.nvim_get_current_win())
			end,
		}),
		vim.api.nvim_create_autocmd("WinClosed", {
			callback = function(args)
				close_float(state, tonumber(args.match) --[[@as integer]])
			end,
		}),
	}
	states[key] = state
	update_current_win()
	return true
end

return M
