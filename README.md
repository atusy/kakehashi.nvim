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

Live features that re-request on every edit can hand the previous result back
to receive cheap delta updates — `get()` merges them and always returns a new
full result (transparently falling back to a full request when the server has
lost the lineage):

```lua
local captures = require("kakehashi.lsp.captures")
local result
local function refresh()
  result = captures.get({ kind = "context", previousResult = result })
end
```

Pass `range` instead to scope the query to a viewport
(`kakehashi/captures/range`; range results carry no `resultId`, so they
cannot seed the delta loop):

```lua
local visible = captures.get({
  kind = "context",
  range = {
    start = { line = vim.fn.line("w0") - 1, character = 0 },
    ["end"] = { line = vim.fn.line("w$"), character = 0 },
  },
})
```

### Keep captures fresh with `kakehashi.lsp.captures.watch()`

Instead of running the delta loop by hand, `watch()` piggybacks on Neovim's
built-in semantic tokens engine: whenever a `textDocument/semanticTokens/full`
or `.../full/delta` request to the kakehashi client goes pending (i.e. the
document changed and the debounce elapsed), the watcher asynchronously mirrors
it with `kakehashi/captures/full` or `kakehashi/captures/full/delta`, keeps
the merged full result in memory, and emits a `KakehashiCapturesUpdate` User
autocmd:

```lua
require("kakehashi.lsp.captures").watch({ kind = "context", injection = true })

vim.api.nvim_create_autocmd("User", {
  pattern = "KakehashiCapturesUpdate",
  callback = function(ev)
    -- ev.data.kind, ev.data.injection, ev.data.bufnr,
    -- ev.data.result (a full KakehashiCapturesResult, or nil
    -- when no language has the kind query)
  end,
})
```

Unlike `get()`, a nil `bufnr` does not mean the current buffer: the watcher
above follows every buffer the client serves, tracking each buffer's delta
lineage independently (`ev.data.bufnr` tells updates apart). Pass `bufnr` to
pin the watcher to a single buffer.

`watch()` returns the watching autocmd id. Calling it again with the same
parameters (client, buffer, kind, injection) returns the existing autocmd
while it is alive, so it is safe to call from repeated setup paths; delete
the autocmd with `vim.api.nvim_del_autocmd()` to stop watching.

`get()` cooperates with a live watcher observing the same target (client,
buffer, kind, injection — buffer-specific or all-buffer): a synchronous
`get()` without `previousResult` continues the watcher's delta lineage
instead of paying for a fresh full traversal, and hands its result back so
the watcher's next delta starts from what `get()` just observed. Range
requests stay outside the lineage as usual.

Semantic tokens must be enabled for the kakehashi client
(`:h vim.lsp.semantic_tokens`, on by default for servers that support them) —
no tokens requests, no capture updates.

### Conceal without a client-side parser via `kakehashi.extra.conceal()`

Tree-sitter conceal (e.g. hiding code-span backticks in markdown) normally
needs a local parser so the highlighter can read `#set! conceal` metadata
from `highlights.scm`. The kakehashi server runs those same queries, so
`conceal()` chains a `captures.watch()` on kind `highlights` with a
`KakehashiCapturesUpdate` subscriber that turns the conceal metadata into
extmarks — capture-level values win over the match-level `#set!` that covers
the whole pattern, mirroring `vim.treesitter.highlighter`:

```lua
require("kakehashi.extra").conceal() -- all buffers of the attached client
vim.wo.conceallevel = 2 -- conceal only shows once 'conceallevel' is set
```

`injection` defaults to `true` because conceal metadata mostly lives in
injected layers such as `markdown_inline`; pass `bufnr` to pin one buffer.
Like `watch()`, repeated calls with the same parameters reuse the live
autocmds; both ids (watcher, applier) are returned so you can delete them to
stop concealing.

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
