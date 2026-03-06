local M = {
	augroup = vim.api.nvim_create_augroup("atusy/kakehashi.nvim", { clear = true }),
}

local function get_vim_lsp_enabled_config(name)
	return vim.lsp._enabled_configs[name].resolved_config
end

---@param name string
---@return vim.lsp.Config | nil
local function get_vim_lsp_config(name)
	local ok, config = pcall(get_vim_lsp_enabled_config, name)
	if ok then
		return config
	end

	return vim.lsp.configs[name]
end

---@param kakehashi vim.lsp.Client
---@param servers string[]
---@param behavior nil | "error" | "keep" | "force" | fun(key: any, prev_value: any?, value: any): any default: "keep"
function M.inherit_nvim_lsp_config(kakehashi, servers, behavior)
	behavior = behavior or "keep"

	---@diagnostic disable-next-line: param-type-mismatch
	kakehashi:request("kakehashi/internal/effectiveConfiguration", vim.empty_dict(), function(err, result)
		if err then
			error(tostring(err))
		end
		local settings = result and result.settings or {}
		local configured_servers = settings.languageServers or {}
		local ignored_servers = { copilot = true, kakehashi = true, denols = true }
		for _, name in pairs(servers) do
			local config = get_vim_lsp_config(name)
			if config and not ignored_servers[name] ~= false then
				configured_servers[name] = vim.tbl_extend(behavior, configured_servers[name] or {}, {
					cmd = config.cmd,
					languages = config.filetypes,
				})
			end
		end
		kakehashi:notify("workspace/didChangeConfiguration", {
			settings = { languageServers = configured_servers },
		})
	end)
end

return M
