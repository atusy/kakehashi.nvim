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

---Run the per-language `queries/<lang>/<kind>.scm` query over the document.
---
---- default: `kakehashi/captures/full`
---- with `range`: `kakehashi/captures/range`, scoped to the viewport
---  (the result carries no resultId — there is no delta over viewports)
---- with `previousResult`: `kakehashi/captures/full/delta`; delta edits are
---  merged over the previous matches so the caller always receives a new
---  full result. A stale lineage (null delta) transparently falls back to a
---  fresh `full` request.
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

	if opts.range then
		return request("kakehashi/captures/range", {
			textDocument = text_document,
			kind = opts.kind,
			range = opts.range,
			injection = opts.injection,
		})
	end

	local function request_full()
		return request("kakehashi/captures/full", {
			textDocument = text_document,
			kind = opts.kind,
			injection = opts.injection,
		})
	end

	if not opts.previousResult then
		return request_full()
	end

	-- no injection param: the lineage (previousResultId) identifies the mode
	local result = request("kakehashi/captures/full/delta", {
		textDocument = text_document,
		kind = opts.kind,
		previousResultId = opts.previousResult.resultId,
	})
	if not result then
		-- lineage lost (stale id, ambiguous mode, or server restart):
		-- the spec says to call full again
		return request_full()
	end
	if result.edits == nil then
		return result -- the server answered with a full result already
	end
	return {
		resultId = result.resultId,
		matches = apply_edits(opts.previousResult.matches, result.edits),
		-- skipped reflects query compilation, which a delta never changes
		skipped = opts.previousResult.skipped,
	}
end

---Keep captures up to date by piggybacking on the editor's semantic tokens
---requests: whenever a semanticTokens full/delta request goes pending, the
---document changed, so the matching captures request is sent asynchronously.
---@param opts { kind: string, client?: vim.lsp.Client, bufnr?: integer, injection?: boolean }
---@return integer autocmd id watching LspRequest
function M.watch(opts)
	assert(opts and opts.kind, "opts.kind is required")
	local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
	local client = opts.client or util.get_client(bufnr)
	local text_document = { uri = vim.uri_from_bufnr(bufnr) }

	local function publish(result)
		vim.api.nvim_exec_autocmds("User", {
			pattern = "KakehashiCapturesUpdate",
			data = { kind = opts.kind, injection = opts.injection, bufnr = bufnr, result = result },
		})
	end

	local function request_full()
		client:request("kakehashi/captures/full", {
			textDocument = text_document,
			kind = opts.kind,
			injection = opts.injection,
		}, function(err, result)
			if not err then
				publish(util.denil(result))
			end
		end, bufnr)
	end

	return vim.api.nvim_create_autocmd("LspRequest", {
		callback = function(ev)
			if ev.data.client_id ~= client.id then
				return
			end
			local request = ev.data.request
			if request.type ~= "pending" or request.bufnr ~= bufnr then
				return
			end
			if request.method == "textDocument/semanticTokens/full" then
				request_full()
			end
		end,
	})
end

return M
