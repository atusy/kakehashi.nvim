local util = require("kakehashi.lsp.util")

local M = {}

---@alias KakehashiCaptureMetadata table<string, string | true>

---@class KakehashiCapture
---@field name string capture name without the '@', e.g. "context"
---@field node { id: string, kind: string } usable with kakehashi.lsp.node accessors
---@field range lsp.Range
---@field metadata? KakehashiCaptureMetadata capture-level #set! values

---@class KakehashiMatch
---@field patternIndex integer pattern within that language's kind query
---@field language string language of the layer this match came from
---@field captures KakehashiCapture[]
---@field metadata? KakehashiCaptureMetadata match-level #set! values

---@class KakehashiCapturesResult
---@field resultId string
---@field matches KakehashiMatch[]
---@field skipped { language: string, startLine: integer, endLine: integer, reason: string }[]

---@class KakehashiCapturesDelta
---@field resultId string
---@field edits { start: integer, deleteCount: integer, data: KakehashiMatch[] }[]

---Splice delta edits over the previous matches, JS-style:
---matches.splice(start, deleteCount, ...data) with 0-based match indices.
---Edits index into the previous array, so they are applied back to front to
---keep earlier indices valid; the previous matches are left untouched.
---@param matches KakehashiMatch[]
---@param edits { start: integer, deleteCount: integer, data: KakehashiMatch[] }[]
---@return KakehashiMatch[]
local function apply_edits(matches, edits)
	local merged = vim.list_slice(matches)
	local ordered = vim.list_slice(edits)
	table.sort(ordered, function(a, b)
		return a.start > b.start
	end)
	for _, edit in ipairs(ordered) do
		for _ = 1, edit.deleteCount do
			table.remove(merged, edit.start + 1)
		end
		for i, data in ipairs(util.denil(edit.data) or {}) do
			table.insert(merged, edit.start + i, data)
		end
	end
	return merged
end

---@param text_document { uri: string }
---@param kind string
---@param injection? boolean
---@return table `kakehashi/captures/full` request params
local function full_params(text_document, kind, injection)
	return { textDocument = text_document, kind = kind, injection = injection }
end

---No injection param here: the lineage (previousResultId) identifies the mode.
---@param text_document { uri: string }
---@param kind string
---@param previous KakehashiCapturesResult
---@return table `kakehashi/captures/full/delta` request params
local function delta_params(text_document, kind, previous)
	return { textDocument = text_document, kind = kind, previousResultId = previous.resultId }
end

---@param a lsp.Position
---@param b lsp.Position
---@return boolean a is at or before b
local function pos_le(a, b)
	return a.line < b.line or (a.line == b.line and a.character <= b.character)
end

---Matches with at least one capture touching the range — the same scoping a
---`kakehashi/captures/range` response applies server-side.
---@param matches KakehashiMatch[]
---@param range lsp.Range
---@return KakehashiMatch[]
local function matches_touching(matches, range)
	return vim.tbl_filter(function(match)
		for _, capture in ipairs(match.captures) do
			if pos_le(capture.range.start, range["end"]) and pos_le(range.start, capture.range["end"]) then
				return true
			end
		end
		return false
	end, matches)
end

---Interpret a non-null `kakehashi/captures/full/delta` response: splice the
---edits over the previous full result, or pass a full answer through as-is.
---@param previous KakehashiCapturesResult
---@param result KakehashiCapturesResult | KakehashiCapturesDelta
---@return KakehashiCapturesResult
local function resolve_delta(previous, result)
	if result.edits == nil then
		-- the server answered with a full result already
		---@cast result KakehashiCapturesResult
		return result
	end
	return {
		resultId = result.resultId,
		matches = apply_edits(previous.matches, result.edits),
		-- skipped reflects query compilation, which a delta never changes
		skipped = previous.skipped,
	}
end

---@class KakehashiCapturesWatcher
---@field autocmd integer the LspRequest autocmd driving the watcher
---@field latest table<integer, KakehashiCapturesResult> latest full result per buffer, the delta lineage
---@field client vim.lsp.Client the client this watcher follows
---@field bufnr? integer the single buffer it follows, nil for an all-buffer watcher

---Live watchers by parameter identity, so repeated watch() calls with the
---same parameters share one autocmd instead of stacking duplicate requests.
---@type table<string, KakehashiCapturesWatcher>
local watchers = {}

---@param watcher KakehashiCapturesWatcher
---@param key string its identity in `watchers`
local function reap_watcher(watcher, key)
	pcall(vim.api.nvim_del_autocmd, watcher.autocmd)
	watchers[key] = nil
end

---Drop a buffer's lineage when the client leaves it, and reap the watcher
---whose work is done: a buffer-specific one with its buffer, an all-buffer
---one once its client serves nothing more. This is what reaps the all-buffer
---watcher in the common single-client case, where the watcher's own
---self-delete never fires (a stopped client emits no further LspRequests).
---@param client_id integer
---@param bufnr integer
local function detach(client_id, bufnr)
	for key, watcher in pairs(watchers) do
		if watcher.client.id == client_id then
			watcher.latest[bufnr] = nil
			if util.reap_on_detach(watcher.client, watcher.bufnr, bufnr) then
				reap_watcher(watcher, key)
			end
		end
	end
end

-- One LspDetach autocmd drives every watcher's teardown; installed lazily so
-- merely requiring this module costs nothing.
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

---@param client_id integer
---@param bufnr? integer nil for a watcher following every buffer of the client
---@param kind string
---@param injection? boolean
---@return string
local function watcher_key(client_id, bufnr, kind, injection)
	return ("%d/%s/%s/%s"):format(client_id, bufnr or "*", kind, tostring(injection == true))
end

---@param autocmd integer
---@return boolean whether the autocmd has not been deleted
local function autocmd_alive(autocmd)
	for _, au in ipairs(vim.api.nvim_get_autocmds({ event = "LspRequest" })) do
		if au.id == autocmd then
			return true
		end
	end
	return false
end

---Find a live watcher observing the target, preferring the buffer-specific
---watcher over an all-buffer one of the same client/kind/injection.
---@param client_id integer
---@param bufnr integer
---@param kind string
---@param injection? boolean
---@return KakehashiCapturesWatcher | nil
local function find_watcher(client_id, bufnr, kind, injection)
	local keys = { watcher_key(client_id, bufnr, kind, injection), watcher_key(client_id, nil, kind, injection) }
	for _, key in ipairs(keys) do
		local watcher = watchers[key]
		if watcher and autocmd_alive(watcher.autocmd) then
			return watcher
		end
	end
	return nil
end

---Run the per-language `queries/<lang>/<kind>.scm` query over the document.
---
---- default: `kakehashi/captures/full`
---- with `range`: `kakehashi/captures/range`, scoped to the viewport
---  (the result carries no resultId — there is no delta over viewports).
---  On a watched buffer the server is asked for one delta instead and the
---  merged result is filtered to the range in memory, which is faster than
---  a fresh range traversal; the shape of the answer is the same.
---- with `previousResult`: `kakehashi/captures/full/delta`; delta edits are
---  merged over the previous matches so the caller always receives a new
---  full result. A stale lineage (null delta) transparently falls back to a
---  fresh `full` request.
---
---When a live watch() observes the same target, get() cooperates with it:
---the watcher's latest result stands in for a missing `previousResult`, and
---the result of a full/delta request becomes the watcher's new lineage.
---@param opts {
---  kind: string,
---  client?: vim.lsp.Client,
---  bufnr?: integer,
---  injection?: boolean,
---  range?: lsp.Range,
---  previousResult?: KakehashiCapturesResult,
---  timeout_ms?: integer,
---}
---@return KakehashiCapturesResult | { matches: KakehashiMatch[], skipped: table[] } | nil
function M.get(opts)
	assert(opts and opts.kind, "opts.kind is required")
	assert(
		not (opts.range and opts.previousResult),
		"opts.range and opts.previousResult are mutually exclusive: range responses carry no resultId to delta from"
	)
	local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
	local client = opts.client or util.get_client(bufnr)
	local timeout_ms = opts.timeout_ms or 1000
	local text_document = { uri = vim.uri_from_bufnr(bufnr) }

	---@param method string
	---@param params table
	---@return any
	local function request(method, params)
		local response = client:request_sync(method, params, timeout_ms, bufnr)
		return util.denil(response and response.result)
	end

	local watcher = find_watcher(client.id, bufnr, opts.kind, opts.injection)

	---Pass a full result through while keeping the watcher's lineage current,
	---so the next watcher-driven delta starts from what get() just observed.
	---@param result KakehashiCapturesResult | nil
	---@return KakehashiCapturesResult | nil
	local function keep(result)
		if watcher then
			watcher.latest[bufnr] = result
		end
		return result
	end

	local function request_full()
		return keep(request("kakehashi/captures/full", full_params(text_document, opts.kind, opts.injection)))
	end

	---@param previous KakehashiCapturesResult
	---@return KakehashiCapturesResult | nil
	local function request_delta(previous)
		local result = request("kakehashi/captures/full/delta", delta_params(text_document, opts.kind, previous))
		if not result then
			-- lineage lost (stale id, ambiguous mode, or server restart):
			-- the spec says to call full again
			return request_full()
		end
		return keep(resolve_delta(previous, result))
	end

	if opts.range then
		local previous = watcher and watcher.latest[bufnr]
		if not previous then
			return request("kakehashi/captures/range", {
				textDocument = text_document,
				kind = opts.kind,
				range = opts.range,
				injection = opts.injection,
			})
		end
		-- a watched buffer answers faster from one delta merged in memory
		-- than from a fresh range traversal — and moves the lineage forward
		local merged = request_delta(previous)
		if not merged then
			return nil
		end
		return { matches = matches_touching(merged.matches, opts.range), skipped = merged.skipped }
	end

	local previous = opts.previousResult or (watcher and watcher.latest[bufnr]) or nil
	if not previous then
		return request_full()
	end
	return request_delta(previous)
end

---Keep captures up to date by piggybacking on the editor's semantic tokens
---requests: whenever a semanticTokens full/delta request goes pending, the
---document changed, so the matching captures request is sent asynchronously.
---Unlike get(), a nil bufnr does not mean the current buffer: the watcher
---then follows every buffer the client serves, tracking each buffer's
---delta lineage independently.
---@param opts { kind: string, client?: vim.lsp.Client, bufnr?: integer, injection?: boolean }
---@return integer autocmd id watching LspRequest
function M.watch(opts)
	assert(opts and opts.kind, "opts.kind is required")
	local client = opts.client or util.get_client(opts.bufnr or vim.api.nvim_get_current_buf())

	local key = watcher_key(client.id, opts.bufnr, opts.kind, opts.injection)
	local existing = watchers[key]
	if existing and autocmd_alive(existing.autocmd) then
		-- Replay the cached results: a subscriber created after the watcher
		-- (e.g. a re-enabled conceal applier) would otherwise wait for the
		-- next edit before hearing anything.
		for bufnr, result in pairs(existing.latest) do
			vim.api.nvim_exec_autocmds("User", {
				pattern = "KakehashiCapturesUpdate",
				data = { kind = opts.kind, injection = opts.injection, bufnr = bufnr, result = result },
			})
		end
		return existing.autocmd
	end

	---@type table<integer, KakehashiCapturesResult> latest full result per buffer, the delta lineage
	local latest = {}

	---@param bufnr integer
	local function publish(bufnr, result)
		latest[bufnr] = result
		vim.api.nvim_exec_autocmds("User", {
			pattern = "KakehashiCapturesUpdate",
			data = { kind = opts.kind, injection = opts.injection, bufnr = bufnr, result = result },
		})
	end

	---@param bufnr integer
	local function request_full(bufnr)
		local params = full_params({ uri = vim.uri_from_bufnr(bufnr) }, opts.kind, opts.injection)
		---@diagnostic disable-next-line: param-type-mismatch
		client:request("kakehashi/captures/full", params, function(err, result)
			if not err then
				publish(bufnr, util.denil(result))
			end
		end, bufnr)
	end

	---@param bufnr integer
	---@param previous KakehashiCapturesResult
	local function request_delta(bufnr, previous)
		local params = delta_params({ uri = vim.uri_from_bufnr(bufnr) }, opts.kind, previous)
		---@diagnostic disable-next-line: param-type-mismatch
		client:request("kakehashi/captures/full/delta", params, function(err, result)
			if err then
				return
			end
			result = util.denil(result)
			if not result then
				-- lineage lost (stale id, ambiguous mode, or server restart):
				-- the spec says to call full again
				return request_full(bufnr)
			end
			publish(bufnr, resolve_delta(previous, result))
		end, bufnr)
	end

	local autocmd = vim.api.nvim_create_autocmd("LspRequest", {
		callback = function(ev)
			-- Reap the watcher once its client is gone. Checked before the
			-- client_id filter on purpose: a stopped client emits no further
			-- LspRequests of its own, so another client's event is the only
			-- thing left to drive this. Returning true deletes the autocmd.
			if client:is_stopped() then
				watchers[key] = nil
				return true
			end
			if ev.data.client_id ~= client.id then
				return
			end
			local request = ev.data.request
			if request.type ~= "pending" or (opts.bufnr and request.bufnr ~= opts.bufnr) then
				return
			end
			if request.method == "textDocument/semanticTokens/full" then
				request_full(request.bufnr)
			elseif request.method == "textDocument/semanticTokens/full/delta" then
				if latest[request.bufnr] then
					request_delta(request.bufnr, latest[request.bufnr])
				else
					request_full(request.bufnr)
				end
			end
		end,
	})
	watchers[key] = { autocmd = autocmd, latest = latest, client = client, bufnr = opts.bufnr }
	ensure_detach_handler()

	-- Seed the buffers already visible: their semantic tokens were requested
	-- when they attached, before this watcher existed, so without an initial
	-- fetch nothing would be published until the next edit.
	if opts.bufnr then
		request_full(opts.bufnr)
	else
		for bufnr in pairs(client.attached_buffers or {}) do
			request_full(bufnr)
		end
	end

	return autocmd
end

return M
