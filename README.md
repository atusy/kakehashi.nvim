# kakehashi.nvim

Enhance the experience of using [kakehashi](https://github.com/atusy/kakehashi) language server.

## Examples

### Query the syntax tree via `kakehashi/node`

`kakehashi.lsp.node.get()` resolves the node at a position (defaults: current
buffer, attached kakehashi client, cursor position) and returns a
`KakehashiNode` whose methods mirror the `kakehashi/node/*` LSP methods
one-for-one — without bundling Tree-sitter on the client side.

```lua
local node = require("kakehashi.lsp.node").get({ injection = true })
if node then
  print(node:kind(), node:text())
  local parent = node:parent()
  local body = node:childByFieldName("body")
  for _, child in ipairs(node:namedChildren() or {}) do
    print(child:toSexp())
  end
end
```

Every method returns `nil` when the node id is no longer resolvable (for
example after an edit destroyed the node); re-acquire it with `get()`.

### Run a Tree-sitter query via `kakehashi/captures/full`

`kakehashi.lsp.captures.get()` runs the per-language
`queries/<lang>/<kind>.scm` query over the whole document in one request.
With `injection = true` every embedded layer is included.

```lua
local result = require("kakehashi.lsp.captures").get({
  kind = "context",
  injection = true,
})
for _, match in ipairs(result and result.matches or {}) do
  for _, capture in ipairs(match.captures) do
    -- capture.node works with the node accessors above
    local node = require("kakehashi.lsp.node").new(capture.node)
    print(match.language, capture.name, node:text())
  end
end
```

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

## Development

Run the test suite headlessly:

```sh
nvim -l tests/run.lua
```
