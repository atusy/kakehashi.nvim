local H = {}

--- Fake vim.lsp.Client recording request_sync calls and replying from a table.
---@param responses table<string, any> method -> result (or function(params) -> result)
function H.fake_client(responses)
	-- the counter is process-global: each test file dofiles this helper, and
	-- per-file counters would collide in registries keyed by client id
	_G.__kakehashi_test_next_client_id = (_G.__kakehashi_test_next_client_id or 0) + 1
	local client = {
		id = _G.__kakehashi_test_next_client_id,
		name = "kakehashi",
		calls = {},
	}
	local function resolve(method, params)
		local response = responses[method]
		if type(response) == "function" then
			response = response(params)
		end
		return response
	end
	function client:request_sync(method, params, timeout_ms, bufnr)
		table.insert(self.calls, { method = method, params = params, timeout_ms = timeout_ms, bufnr = bufnr })
		return { err = nil, result = resolve(method, params) }, nil
	end
	function client:request(method, params, handler, bufnr)
		table.insert(self.calls, { method = method, params = params, bufnr = bufnr })
		handler(nil, resolve(method, params), { method = method, bufnr = bufnr, client_id = self.id })
		return true, #self.calls
	end
	function client:is_stopped()
		return self.stopped == true
	end
	return client
end

--- Fire an LspRequest autocmd as Neovim would for a request status change.
---@param client { id: integer } the client the request belongs to
---@param request { type: string, bufnr: integer, method: string }
function H.fire_lsp_request(client, request)
	vim.api.nvim_exec_autocmds("LspRequest", {
		data = { client_id = client.id, request_id = 1, request = request },
	})
end

function H.scratch_buf(name)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(buf, name or (vim.fn.tempname() .. ".md"))
	return buf
end

function H.eq(expected, actual, msg)
	if not vim.deep_equal(expected, actual) then
		error(
			("%sexpected %s, got %s"):format(
				msg and (msg .. ": ") or "",
				vim.inspect(expected),
				vim.inspect(actual)
			),
			2
		)
	end
end

return H
