local H = {}

--- Fake vim.lsp.Client recording request_sync calls and replying from a table.
---@param responses table<string, any> method -> result (or function(params) -> result)
function H.fake_client(responses)
	local client = {
		name = "kakehashi",
		calls = {},
	}
	function client:request_sync(method, params, timeout_ms, bufnr)
		table.insert(self.calls, { method = method, params = params, timeout_ms = timeout_ms, bufnr = bufnr })
		local response = responses[method]
		if type(response) == "function" then
			response = response(params)
		end
		return { err = nil, result = response }, nil
	end
	return client
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
