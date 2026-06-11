; Derived from nvim-treesitter-endwise (MIT) queries/elixir/endwise.scm.

((do_block "do" @endwise.cursor) @endwise
  (#set! endwise "end"))

((ERROR) @endwise.error)

((MISSING) @endwise.missing)
