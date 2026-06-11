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
cannot seed the delta loop). When a live watcher observes the buffer, the
range answer is derived from one cheap delta filtered in memory instead of
a fresh range traversal — same shape, fewer server cycles:

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

A fresh watcher seeds itself immediately: buffers it can already see (the
pinned `bufnr`, or every attached buffer) get one `captures/full` on
creation, because their semantic tokens were requested before the watcher
existed and nothing else would be published until the next edit.

`watch()` returns the watching autocmd id. Calling it again with the same
parameters (client, buffer, kind, injection) returns the existing autocmd
while it is alive — and replays the cached results so a subscriber created
after the watcher (e.g. a re-enabled `conceal.toggle()`) hears the current
state right away. It is safe to call from repeated setup paths; delete
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

### Conceal without a client-side parser via `kakehashi.extra.conceal.toggle()`

Tree-sitter conceal (e.g. hiding code-span backticks in markdown) normally
needs a local parser so the highlighter can read `#set! conceal` metadata
from `highlights.scm`. The kakehashi server runs those same queries, so
`conceal.toggle()` chains a `captures.watch()` on kind `highlights` with a
`KakehashiCapturesUpdate` subscriber that turns the conceal metadata into
extmarks — capture-level values win over the match-level `#set!` that covers
the whole pattern, mirroring `vim.treesitter.highlighter`:

```lua
require("kakehashi.extra.conceal").toggle() -- all buffers of the attached client
vim.wo.conceallevel = 2 -- conceal only shows once 'conceallevel' is set
```

`injection` defaults to `true` because conceal metadata mostly lives in
injected layers such as `markdown_inline`; pass `bufnr` to pin one buffer.
Calling `toggle()` again with the same parameters (client, buffer, injection)
turns concealing off and removes its extmarks; it returns `true` when the
call enabled concealing. The underlying watcher keeps running across toggles —
watchers are shared by parameters, and a re-enable picks the live result up
on the next update.

### Sticky context headers via `kakehashi.extra.context.toggle()`

The nvim-treesitter-context experience — the function/class header you are
inside stays pinned at the top of the window — without a client-side parser:
the kakehashi server runs your `queries/<lang>/context.scm` (add it to the
server's `searchPaths`; the `@context` captures follow nvim-treesitter-context
conventions), a `captures.watch()` on kind `context` keeps the captures
fresh, and window events re-derive which headers scrolled off above the
topline into a floating window:

```lua
require("kakehashi.extra.context").toggle() -- all buffers of the attached client
```

Each header is a single-line float showing the real buffer scrolled to the
header row, so kakehashi's own decorations — semantic token highlights and
`conceal.toggle()` extmarks — render in the context natively, with no
text or highlight copying. Headers stack outermost-first, each pinned header
is accounted for when deciding what the first visible line is, and the stack
never covers the cursor line. Pass `max_lines` to cap the stack and `bufnr`
to pin one buffer; the floats are tinted with `KakehashiContext` (links to
`NormalFloat`). Like `conceal.toggle()`, calling it again with the same
parameters turns the headers off, and the underlying watcher keeps running
across toggles.

### Context-aware 'commentstring' via `kakehashi.extra.commentstring.get()`

What nvim-ts-context-commentstring derives from a client-side parse — `-- %s`
inside a lua block of a markdown file, `{/* %s */}` inside JSX — decided by
the server instead. This plugin ships `queries/<lang>/commentstring.scm` for
120+ languages (values sourced from Comment.nvim's tables, roots validated
against the real grammars); each pattern captures the nodes a commentstring
applies to and states the value with `#set! commentstring "..."`. Put the
plugin directory on the server's `searchPaths` and extend or override per
language by shadowing the file in an earlier path.

`get()` synchronously runs the query (`kakehashi/captures/full`) and returns
the commentstring of the innermost capture containing the given range
(capture metadata wins over match-level `#set!`), or `nil` when nothing
covers the range — keep your own fallback:

```lua
local commentstring = require("kakehashi.extra.commentstring")

-- at the cursor (the default range)
vim.bo.commentstring = commentstring.get() or vim.bo.commentstring

-- for the lines about to be commented, e.g. a visual selection
local cs = commentstring.get({
  range = {
    start = { line = vim.fn.line("v") - 1, character = 0 },
    ["end"] = { line = vim.fn.line("."), character = 0 },
  },
})
```

Passing the whole selection matters: a selection spanning out of a JSX
element into the surrounding function is not contained by the `jsx_element`
capture, so the javascript `// %s` wins instead.

`watch()` makes `get()` cheap: it is exactly a `captures.watch()` on kind
`commentstring`, and `get()` cooperates with that watcher — each call shrinks
to a `full/delta` request merged over the watcher's in-memory result instead
of a full traversal, and always reflects the current document. It never
touches the 'commentstring' option; applying the value stays your business.

```lua
require("kakehashi.extra.commentstring").watch()
```

The returned autocmd id, the all-buffer default, and the
reuse-by-parameters semantics are `captures.watch()`'s own.

Integrations stay in your config — for example a
[Comment.nvim](https://github.com/numToStr/Comment.nvim) `pre_hook`
replacing nvim-ts-context-commentstring. Comment.nvim only falls back to
`vim.treesitter` (a client-side parse) when the `pre_hook` returns nil, so a
total hook — kakehashi first, then Comment.nvim's plain filetype table, then
the 'commentstring' option — keeps commenting entirely server-driven:

```lua
require("Comment").setup({
  mappings = false,
  pre_hook = function(ctx)
    local blockwise = ctx.ctype == require("Comment.utils").ctype.blockwise
    local ok, commentstring = pcall(function()
      local bufnr = vim.api.nvim_get_current_buf()
      -- consult the commented rows, excluding indentation and trailing
      -- blanks, so the range stays inside the capture holding the code
      local first = vim.api.nvim_buf_get_lines(bufnr, ctx.range.srow - 1, ctx.range.srow, false)[1] or ""
      local last = ctx.range.srow == ctx.range.erow and first
        or vim.api.nvim_buf_get_lines(bufnr, ctx.range.erow - 1, ctx.range.erow, false)[1]
        or ""
      return require("kakehashi.extra.commentstring").get({
        bufnr = bufnr,
        range = {
          start = { line = ctx.range.srow - 1, character = (first:find("%S") or 1) - 1 },
          ["end"] = {
            line = ctx.range.erow - 1,
            character = vim.str_utfindex(last, "utf-16", #(last:gsub("%s+$", "")), false),
          },
        },
      })
    end)
    -- blockwise needs a closing side ("{/* %s */}" has one, "-- %s" not)
    if ok and commentstring and (not blockwise or commentstring:find("%%s%s*%S")) then
      return commentstring
    end
    -- the fallbacks live here in the hook: ft.get is a plain table lookup
    return require("Comment.ft").get(vim.bo.filetype, ctx.ctype)
      or (not blockwise and vim.bo.commentstring)
      or error(vim.bo.filetype .. " doesn't support block comments!")
  end,
})
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
