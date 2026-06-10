local util = require("kakehashi.lsp.util")

local M = {}

---A handle to a Tree-sitter node held by the kakehashi language server.
---The `id` stays valid across edits as long as the node survives; any method
---returns nil once the id is no longer resolvable (re-acquire via `get()`).
---Methods mirror the `kakehashi/node/*` LSP methods one-for-one.
---@class KakehashiNode
---@field id string
---@field client vim.lsp.Client
---@field bufnr integer
---@field timeout_ms integer
---@field kind fun(self: KakehashiNode): string | nil
---@field grammarName fun(self: KakehashiNode): string | nil
---@field isNamed fun(self: KakehashiNode): boolean | nil
---@field isExtra fun(self: KakehashiNode): boolean | nil
---@field hasError fun(self: KakehashiNode): boolean | nil
---@field isError fun(self: KakehashiNode): boolean | nil
---@field isMissing fun(self: KakehashiNode): boolean | nil
---@field startByte fun(self: KakehashiNode): integer | nil
---@field endByte fun(self: KakehashiNode): integer | nil
---@field childCount fun(self: KakehashiNode): integer | nil
---@field namedChildCount fun(self: KakehashiNode): integer | nil
---@field descendantCount fun(self: KakehashiNode): integer | nil
---@field toSexp fun(self: KakehashiNode): string | nil
---@field text fun(self: KakehashiNode): string | nil
---@field startPosition fun(self: KakehashiNode): lsp.Position | nil
---@field endPosition fun(self: KakehashiNode): lsp.Position | nil
---@field byteRange fun(self: KakehashiNode): { startByte: integer, endByte: integer } | nil
---@field range fun(self: KakehashiNode): lsp.Range | nil
---@field parent fun(self: KakehashiNode): KakehashiNode | nil
---@field nextSibling fun(self: KakehashiNode): KakehashiNode | nil
---@field prevSibling fun(self: KakehashiNode): KakehashiNode | nil
---@field nextNamedSibling fun(self: KakehashiNode): KakehashiNode | nil
---@field prevNamedSibling fun(self: KakehashiNode): KakehashiNode | nil
---@field child fun(self: KakehashiNode, index: integer): KakehashiNode | nil
---@field namedChild fun(self: KakehashiNode, index: integer): KakehashiNode | nil
---@field firstChildForByte fun(self: KakehashiNode, byte: integer): KakehashiNode | nil
---@field descendantForByteRange fun(self: KakehashiNode, start_byte: integer, end_byte: integer): KakehashiNode | nil
---@field namedDescendantForByteRange fun(self: KakehashiNode, start_byte: integer, end_byte: integer): KakehashiNode | nil
---@field childByFieldName fun(self: KakehashiNode, name: string): KakehashiNode | nil
---@field descendantForPointRange fun(self: KakehashiNode, start: lsp.Position, end_: lsp.Position): KakehashiNode | nil
---@field namedDescendantForPointRange fun(self: KakehashiNode, start: lsp.Position, end_: lsp.Position): KakehashiNode | nil
---@field children fun(self: KakehashiNode): KakehashiNode[] | nil
---@field namedChildren fun(self: KakehashiNode): KakehashiNode[] | nil
---@field childrenByFieldName fun(self: KakehashiNode, name: string): KakehashiNode[] | nil
---@field fieldNameForChild fun(self: KakehashiNode, index: integer): string | nil
---@field fieldNameForNamedChild fun(self: KakehashiNode, index: integer): string | nil
local KakehashiNode = {}
KakehashiNode.__index = KakehashiNode

local denil = util.denil

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

---@param node KakehashiNode
---@param method string method name without the "kakehashi/node/" prefix
---@param extra_params table | nil
---@return any nil when the id is not currently resolvable
local function request(node, method, extra_params)
	local params = vim.tbl_extend("force", {
		textDocument = { uri = vim.uri_from_bufnr(node.bufnr) },
		id = node.id,
	}, extra_params or {})
	local response = node.client:request_sync("kakehashi/node/" .. method, params, node.timeout_ms, node.bufnr)
	return denil(response and response.result)
end

-- Introspection: { method = field to unwrap from the single-field result }
local scalar_methods = {
	kind = "kind",
	grammarName = "grammarName",
	isNamed = "isNamed",
	isExtra = "isExtra",
	hasError = "hasError",
	isError = "isError",
	isMissing = "isMissing",
	startByte = "startByte",
	endByte = "endByte",
	childCount = "childCount",
	namedChildCount = "namedChildCount",
	descendantCount = "descendantCount",
	toSexp = "sexp",
	text = "text",
	startPosition = "startPosition",
	endPosition = "endPosition",
	fieldNameForChild = "fieldName",
	fieldNameForNamedChild = "fieldName",
}

-- Whole-result objects: byteRange = { startByte, endByte }, range = { start, end }
local object_methods = { "byteRange", "range" }

-- Navigation returning NodeInfo | null: { method = positional argument names }
local node_methods = {
	parent = {},
	nextSibling = {},
	prevSibling = {},
	nextNamedSibling = {},
	prevNamedSibling = {},
	child = { "index" },
	namedChild = { "index" },
	firstChildForByte = { "byte" },
	descendantForByteRange = { "startByte", "endByte" },
	namedDescendantForByteRange = { "startByte", "endByte" },
	childByFieldName = { "name" },
	descendantForPointRange = { "start", "end" },
	namedDescendantForPointRange = { "start", "end" },
}

-- Navigation returning NodeInfo[] | null
local node_list_methods = {
	children = {},
	namedChildren = {},
	childrenByFieldName = { "name" },
}

---@param param_names string[]
---@return fun(...): table maps positional arguments to named request params
local function pack_params(param_names)
	return function(...)
		local params = {}
		for i, key in ipairs(param_names) do
			params[key] = select(i, ...)
		end
		return params
	end
end

for name, field in pairs(scalar_methods) do
	local pack = pack_params(name:find("^fieldNameFor") and { "index" } or {})
	KakehashiNode[name] = function(self, ...)
		local result = request(self, name, pack(...))
		return result and denil(result[field])
	end
end

for _, name in ipairs(object_methods) do
	KakehashiNode[name] = function(self)
		return request(self, name)
	end
end

for name, param_names in pairs(node_methods) do
	local pack = pack_params(param_names)
	KakehashiNode[name] = function(self, ...)
		local info = request(self, name, pack(...))
		return info and new_node(info, self)
	end
end

for name, param_names in pairs(node_list_methods) do
	local pack = pack_params(param_names)
	KakehashiNode[name] = function(self, ...)
		local infos = request(self, name, pack(...))
		return infos
			and vim.tbl_map(function(info)
				return new_node(info, self)
			end, infos)
	end
end

---Wrap an already-known NodeInfo (e.g. from kakehashi.lsp.captures) into a
---KakehashiNode so the `kakehashi/node/*` accessors become available on it.
---@param info { id: string, kind?: string }
---@param opts? { client?: vim.lsp.Client, bufnr?: integer, timeout_ms?: integer }
---@return KakehashiNode
function M.new(info, opts)
	opts = opts or {}
	local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
	return new_node(info, {
		client = opts.client or util.get_client(bufnr),
		bufnr = bufnr,
		timeout_ms = opts.timeout_ms or 1000,
	})
end

---Resolve the smallest node at a position via `kakehashi/node`.
---Defaults: current buffer, the kakehashi client attached to it, and the
---cursor position of the current window (UTF-16, like every LSP position).
---@param opts? {
---  client?: vim.lsp.Client,
---  bufnr?: integer,
---  position?: lsp.Position,
---  injection?: boolean | integer,
---  timeout_ms?: integer,
---}
---@return KakehashiNode | nil
function M.get(opts)
	opts = opts or {}
	local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
	local client = opts.client or util.get_client(bufnr)
	local position = opts.position or vim.lsp.util.make_position_params(0, "utf-16").position
	local timeout_ms = opts.timeout_ms or 1000
	local response = client:request_sync("kakehashi/node", {
		textDocument = { uri = vim.uri_from_bufnr(bufnr) },
		position = position,
		injection = opts.injection,
	}, timeout_ms, bufnr)
	local info = denil(response and response.result)
	if not info then
		return nil
	end
	return new_node(info, { client = client, bufnr = bufnr, timeout_ms = timeout_ms })
end

return M
