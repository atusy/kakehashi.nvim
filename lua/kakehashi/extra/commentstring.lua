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

local find_watcher

---Context-aware 'commentstring' the way nvim-ts-context-commentstring
---computes it, but decided by `queries/<lang>/commentstring.scm` on the
---kakehashi server (this plugin ships a starter set under queries/; put the
---plugin directory on the server's searchPaths): each query captures the
---nodes a commentstring applies to and states the value with
---`#set! commentstring "..."`. The range narrows the decision — pass the
---selection about to be commented; it defaults to the cursor position.
---
---When a live watch() observes the same target, the answer comes from the
---watched full-document result without any request; otherwise a synchronous
---`kakehashi/captures/range` request is made.
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
	local injection = opts.injection ~= false
	local range = opts.range or cursor_range(client.offset_encoding or "utf-16")

	local watcher = find_watcher(client.id, bufnr, injection)
	local watched = watcher and watcher.latest[bufnr]
	if watched ~= nil then
		return resolve(watched or nil, range)
	end

	local result = require("kakehashi.lsp.captures").get({
		kind = "commentstring",
		client = client,
		bufnr = bufnr,
		range = range,
		injection = injection,
		timeout_ms = opts.timeout_ms,
	})
	return resolve(result, range)
end

---@class KakehashiCommentstringWatcher
---@field autocmd integer User KakehashiCapturesUpdate subscriber
---@field latest table<integer, KakehashiCapturesResult | false> last watched result per buffer; false records a null result

---Live watchers by parameter identity, mirroring captures.watch(): repeated
---watch() calls with the same parameters share one subscriber.
---@type table<string, KakehashiCommentstringWatcher>
local watchers = {}

---@param autocmd integer
---@return boolean whether the autocmd has not been deleted
local function watcher_alive(autocmd)
	local subscribers = vim.api.nvim_get_autocmds({ event = "User", pattern = "KakehashiCapturesUpdate" })
	for _, au in ipairs(subscribers) do
		if au.id == autocmd then
			return true
		end
	end
	return false
end

---@param client_id integer
---@param bufnr? integer
---@param injection boolean
---@return string
local function watcher_key(client_id, bufnr, injection)
	return ("%d/%s/%s"):format(client_id, bufnr or "*", tostring(injection))
end

---Find a live watcher observing the target, preferring the buffer-pinned
---watcher over an all-buffer one of the same client/injection.
---(forward-declared above get(), which consults it before requesting)
---@param client_id integer
---@param bufnr integer
---@param injection boolean
---@return KakehashiCommentstringWatcher | nil
function find_watcher(client_id, bufnr, injection)
	local keys = { watcher_key(client_id, bufnr, injection), watcher_key(client_id, nil, injection) }
	for _, key in ipairs(keys) do
		local watcher = watchers[key]
		if watcher and watcher_alive(watcher.autocmd) then
			return watcher
		end
	end
	return nil
end

---Make get() answer without a request: a captures.watch() on kind
---"commentstring" keeps the full-document captures fresh (cheap deltas
---piggybacking on semantic tokens), and get() resolves any range from the
---watched result in memory instead of asking the server. The 'commentstring'
---option is never touched — applying the value stays the caller's business.
---Freshness rides on the semantic tokens cadence, so an answer right after
---an edit may lag one update behind.
---Unlike get(), a nil bufnr does not mean the current buffer: the watcher
---then follows every buffer the client serves. Delete the autocmd with
---vim.api.nvim_del_autocmd() to stop watching; the underlying captures
---watcher keeps running, like the other extra modules.
---@param opts? { client?: vim.lsp.Client, bufnr?: integer, injection?: boolean } injection defaults to true
---@return integer autocmd id of the User KakehashiCapturesUpdate subscriber
function M.watch(opts)
	opts = opts or {}
	local injection = opts.injection ~= false
	local client = opts.client or util.get_client(opts.bufnr or vim.api.nvim_get_current_buf())

	local key = watcher_key(client.id, opts.bufnr, injection)
	local existing = watchers[key]
	if existing and watcher_alive(existing.autocmd) then
		return existing.autocmd
	end

	require("kakehashi.lsp.captures").watch({
		kind = "commentstring",
		client = client,
		bufnr = opts.bufnr,
		injection = injection,
	})

	---@type table<integer, KakehashiCapturesResult | false>
	local latest = {}
	local autocmd = vim.api.nvim_create_autocmd("User", {
		pattern = "KakehashiCapturesUpdate",
		callback = function(ev)
			if ev.data.kind ~= "commentstring" or ev.data.injection ~= injection then
				return
			end
			if opts.bufnr and ev.data.bufnr ~= opts.bufnr then
				return
			end
			-- false keeps a null result distinguishable from "never watched",
			-- which would send get() into its fallback request
			latest[ev.data.bufnr] = ev.data.result or false
		end,
	})
	watchers[key] = { autocmd = autocmd, latest = latest }
	return autocmd
end

return M
