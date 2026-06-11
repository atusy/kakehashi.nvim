# kakehashi.nvim

Enhance the experience of using the
[kakehashi](https://github.com/atusy/kakehashi) language server with Neovim.

## Setup: lazily configure bridged language servers

kakehashi bridges other language servers, and configuring them twice — once
for Neovim, once for kakehashi — would be a chore. `inherit_nvim_lsp_config`
hands your `vim.lsp.config` definitions over to the server, so kakehashi
serves the same language servers you already enabled:

```lua
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if client and client.name == "kakehashi" then
      require("kakehashi").inherit_nvim_lsp_config(
        client,
        vim.tbl_keys(vim.lsp._enabled_configs),
        "keep"
      )
    end
  end,
})
```

## Features

The server parses documents with tree-sitter, so these work without
installing tree-sitter parsers on the client:

- **Conceal** — `require("kakehashi.extra.conceal").toggle()` hides text the
  way the highlights queries direct (e.g. code-span backticks in markdown).
- **Sticky context headers** — `require("kakehashi.extra.context").toggle()`
  pins the headers of enclosing functions/classes/sections at the top of the
  window, like nvim-treesitter-context.
- **Context-aware 'commentstring'** —
  `require("kakehashi.extra.commentstring").get()` answers `-- %s` inside a
  lua block of a markdown file and `{/* %s */}` inside JSX, like
  nvim-ts-context-commentstring. Queries bundled for 120+ languages, with a
  Comment.nvim recipe included.
- **Endwise** — `require("kakehashi.extra.endwise").get()` tells which
  closing keyword (`end`, `fi`, `endif`, ...) the construct at the cursor
  still needs, like nvim-treesitter-endwise.
- **Queries and nodes** — `kakehashi.lsp.captures` runs any query kind over
  the document (one-shot, incremental, or watched), and `kakehashi.lsp.node`
  inspects and navigates syntax nodes.

See `:h kakehashi` for the full reference, prerequisites, and recipes.

## Development

Run the test suite headlessly:

```sh
nvim -l tests/run.lua
```
