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

---Interpret a non-null `kakehashi/captures/full/delta` response: splice the
---edits over the previous full result, or pass a full answer through as-is.
---@param previous KakehashiCapturesResult
---@param result KakehashiCapturesResult | KakehashiCapturesDelta
---@return KakehashiCapturesResult
local function resolve_delta(previous, result)
	if result.edits == nil then
		return result -- the server answered with a full result already
	end
	return {
		resultId = result.resultId,
		matches = apply_edits(previous.matches, result.edits),
		-- skipped reflects query compilation, which a delta never changes
		skipped = previous.skipped,
	}
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
		return request("kakehashi/captures/full", full_params(text_document, opts.kind, opts.injection))
	end

	if not opts.previousResult then
		return request_full()
	end

	local result = request("kakehashi/captures/full/delta", delta_params(text_document, opts.kind, opts.previousResult))
	if not result then
		-- lineage lost (stale id, ambiguous mode, or server restart):
		-- the spec says to call full again
		return request_full()
	end
	return resolve_delta(opts.previousResult, result)
end

---Live watchers by parameter identity, so repeated watch() calls with the
---same parameters share one autocmd instead of stacking duplicate requests.
---@type table<string, integer>
local watchers = {}

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

	local key = ("%d/%d/%s/%s"):format(client.id, bufnr, opts.kind, tostring(opts.injection == true))
	local existing = watchers[key]
	if existing and autocmd_alive(existing) then
		return existing
	end

	---@type KakehashiCapturesResult? latest full result, the delta lineage
	local latest

	local function publish(result)
		latest = result
		vim.api.nvim_exec_autocmds("User", {
			pattern = "KakehashiCapturesUpdate",
			data = { kind = opts.kind, injection = opts.injection, bufnr = bufnr, result = result },
		})
	end

	local function request_full()
		local params = full_params(text_document, opts.kind, opts.injection)
		client:request("kakehashi/captures/full", params, function(err, result)
			if not err then
				publish(util.denil(result))
			end
		end, bufnr)
	end

	---@param previous KakehashiCapturesResult
	local function request_delta(previous)
		local params = delta_params(text_document, opts.kind, previous)
		client:request("kakehashi/captures/full/delta", params, function(err, result)
			if err then
				return
			end
			result = util.denil(result)
			if not result then
				-- lineage lost (stale id, ambiguous mode, or server restart):
				-- the spec says to call full again
				return request_full()
			end
			publish(resolve_delta(previous, result))
		end, bufnr)
	end

	local autocmd = vim.api.nvim_create_autocmd("LspRequest", {
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
			elseif request.method == "textDocument/semanticTokens/full/delta" then
				if latest then
					request_delta(latest)
				else
					request_full()
				end
			end
		end,
	})
	watchers[key] = autocmd
	return autocmd
end

return M
