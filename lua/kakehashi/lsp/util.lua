local M = {}

---@param value any
---@return any nil for JSON null (vim.NIL), the value otherwise
function M.denil(value)
	if value == vim.NIL then
		return nil
	end
	return value
end

---Whether a subscriber following `followed` (a buffer, or nil for every buffer
---the client serves) is done once `client` leaves `detached`: a buffer-specific
---one when its own buffer goes, an all-buffer one only once the client serves
---nothing more — which, in a single-client setup, is what reaps the all-buffer
---subscriber at all (a stopped client emits no further LspRequests to self-reap on).
---
---`detached` is excluded from the "serves anything more" scan on purpose:
---Neovim fires LspDetach (Client:_on_detach) before it removes the buffer from
---`attached_buffers`, so the detaching buffer is still listed here; trusting the
---table would never see the last buffer leave. The `is_stopped()` short-circuit
---covers client stop/exit, where every buffer detaches and the rpc is closing.
---@param client vim.lsp.Client
---@param followed integer | nil the buffer the subscriber follows, nil for all
---@param detached integer the buffer just detached
---@return boolean
function M.reap_on_detach(client, followed, detached)
	if followed ~= nil then
		return followed == detached
	end
	if client:is_stopped() then
		return true
	end
	for bufnr in pairs(client.attached_buffers or {}) do
		if bufnr ~= detached then
			return false -- another buffer keeps the all-buffer subscriber working
		end
	end
	return true
end

---@param bufnr integer
---@return vim.lsp.Client
function M.get_client(bufnr)
	return assert(
		vim.lsp.get_clients({ bufnr = bufnr, name = "kakehashi" })[1],
		("no kakehashi client attached to buffer %d"):format(bufnr or -1)
	)
end

return M
