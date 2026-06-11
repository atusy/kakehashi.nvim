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
---`#set! commentstring "..."`. The range narrows the decision — pass the
---selection about to be commented; it defaults to the cursor position.
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
		range = range,
		injection = opts.injection ~= false,
		timeout_ms = opts.timeout_ms,
	})
	return resolve(result, range)
end

---Live watchers by parameter identity, mirroring captures.watch(): repeated
---watch() calls with the same parameters share one autocmd.
---@type table<string, integer>
local watchers = {}

---@param autocmd integer
---@return boolean whether the autocmd has not been deleted
local function watcher_alive(autocmd)
	for _, au in ipairs(vim.api.nvim_get_autocmds({ event = "CursorMoved" })) do
		if au.id == autocmd then
			return true
		end
	end
	return false
end

---Keep the buffer-local 'commentstring' in sync with the cursor context:
---cursor movement and buffer entry asynchronously run get()'s request at the
---cursor and apply the answer, so :h commenting and plugins reading the
---option pick the contextual value up. Outside every capture the option
---returns to what it was before the watcher first touched the buffer.
---Unlike get(), a nil bufnr does not mean the current buffer: the watcher
---then follows every buffer the client is attached to. Delete the autocmd
---with vim.api.nvim_del_autocmd() to stop watching.
---@param opts? { client?: vim.lsp.Client, bufnr?: integer, injection?: boolean } injection defaults to true
---@return integer autocmd id watching cursor and buffer events
function M.watch(opts)
	opts = opts or {}
	local injection = opts.injection ~= false
	local client = opts.client or util.get_client(opts.bufnr or vim.api.nvim_get_current_buf())

	local key = ("%d/%s/%s"):format(client.id, opts.bufnr or "*", tostring(injection))
	local existing = watchers[key]
	if existing and watcher_alive(existing) then
		return existing
	end

	---@type table<integer, string> 'commentstring' before the watcher first touched the buffer
	local originals = {}

	local function update()
		local bufnr = vim.api.nvim_get_current_buf()
		if opts.bufnr then
			if bufnr ~= opts.bufnr then
				return
			end
		elseif not (client.attached_buffers and client.attached_buffers[bufnr]) then
			return
		end
		local range = cursor_range(client.offset_encoding or "utf-16")
		local params = {
			textDocument = { uri = vim.uri_from_bufnr(bufnr) },
			kind = "commentstring",
			range = range,
			injection = injection,
		}
		---@diagnostic disable-next-line: param-type-mismatch
		client:request("kakehashi/captures/range", params, function(err, result)
			if err or not vim.api.nvim_buf_is_valid(bufnr) then
				return
			end
			if originals[bufnr] == nil then
				originals[bufnr] = vim.bo[bufnr].commentstring
			end
			vim.bo[bufnr].commentstring = resolve(util.denil(result), range) or originals[bufnr]
		end, bufnr)
	end

	local autocmd = vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufEnter" }, {
		callback = update,
	})
	watchers[key] = autocmd
	update()
	return autocmd
end

return M
