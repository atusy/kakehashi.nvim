local M = {}

---A handle to a Tree-sitter node held by the kakehashi language server.
---The `id` stays valid across edits as long as the node survives.
---@class KakehashiNode
---@field id string
---@field client vim.lsp.Client
---@field bufnr integer
---@field timeout_ms integer
local KakehashiNode = {}
KakehashiNode.__index = KakehashiNode

---@param info { id: string, kind: string }
---@param ctx { client: vim.lsp.Client, bufnr: integer, timeout_ms: integer }
---@return KakehashiNode
local function new_node(info, ctx)
	return setmetatable({
		id = info.id,
		client = ctx.client,
		bufnr = ctx.bufnr,
		timeout_ms = ctx.timeout_ms,
	}, KakehashiNode)
end

---Resolve the smallest node at a position via `kakehashi/node`.
---@param opts {
---  client: vim.lsp.Client,
---  bufnr?: integer,
---  position: lsp.Position,
---  injection?: boolean | integer,
---  timeout_ms?: integer,
---}
---@return KakehashiNode | nil
function M.get(opts)
	local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
	local timeout_ms = opts.timeout_ms or 1000
	local response = opts.client:request_sync("kakehashi/node", {
		textDocument = { uri = vim.uri_from_bufnr(bufnr) },
		position = opts.position,
		injection = opts.injection,
	}, timeout_ms, bufnr)
	local info = response and response.result
	if not info then
		return nil
	end
	return new_node(info, { client = opts.client, bufnr = bufnr, timeout_ms = timeout_ms })
end

return M
