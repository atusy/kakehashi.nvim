# kakehashi.nvim

Enhance the experience of using [kakehashi](https://github.com/atusy/kakehashi) language server.

## Examples

### Lazily setup bridged language servers by inheriting `vim.lsp.config`.

```lua
local servers = { "lua_ls" } -- or vim.tbl_keys(vim.lsp._enabled_configs)

vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if client and client.name == "kakehashi" then
      require("kakehashi").inherit_nvim_lsp_config(
        client,
        servers,
        "keep"
      )
    end
  end,
})
```
