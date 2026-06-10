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

---Run the per-language `queries/<lang>/<kind>.scm` query over the document
---via `kakehashi/captures/full`.
---@param opts {
---  kind: string,
---  client?: vim.lsp.Client,
---  bufnr?: integer,
---  injection?: boolean,
---  timeout_ms?: integer,
---}
---@return KakehashiCapturesResult | nil nil when the document is not open or no involved language has the kind query
function M.get(opts)
	assert(opts and opts.kind, "opts.kind is required")
	local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
	local client = opts.client or util.get_client(bufnr)
	local response = client:request_sync("kakehashi/captures/full", {
		textDocument = { uri = vim.uri_from_bufnr(bufnr) },
		kind = opts.kind,
		injection = opts.injection,
	}, opts.timeout_ms or 1000, bufnr)
	return util.denil(response and response.result)
end

return M
