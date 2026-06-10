local M = {}

---@param value any
---@return any nil for JSON null (vim.NIL), the value otherwise
function M.denil(value)
	if value == vim.NIL then
		return nil
	end
	return value
end

---@param bufnr integer
---@return vim.lsp.Client
function M.get_client(bufnr)
	return assert(
		vim.lsp.get_clients({ bufnr = bufnr, name = "kakehashi" })[1],
		("no kakehashi client attached to buffer %d"):format(bufnr)
	)
end

return M
