; Derived from nvim-treesitter-endwise (MIT) queries/fish/endwise.scm.

((function_definition name: (_) option: (_) @endwise.cursor) @endwise
  (#set! endwise "end"))

((function_definition name: (_) @endwise.cursor) @endwise
  (#set! endwise "end"))

((while_statement condition: (_) @endwise.cursor) @endwise
  (#set! endwise "end"))

((for_statement variable: (_) value: (_) @endwise.cursor) @endwise
  (#set! endwise "end"))

((begin_statement (_) @endwise.cursor) @endwise
  (#set! endwise "end"))

((switch_statement (_) @endwise.cursor) @endwise
  (#set! endwise "end"))

((if_statement condition: (_) @endwise.cursor) @endwise
  (#set! endwise "end"))

((ERROR ("function" . (_)+ @endwise.cursor))
  (#set! endwise "end"))

((ERROR ("while" . (_) @endwise.cursor))
  (#set! endwise "end"))

((ERROR ("for" . (_) . "in" . (_) @endwise.cursor))
  (#set! endwise "end"))

((ERROR ("begin" @endwise.cursor))
  (#set! endwise "end"))

((ERROR ("switch" . (_) @endwise.cursor))
  (#set! endwise "end"))

((ERROR ("if" . (_) @endwise.cursor))
  (#set! endwise "end"))

((ERROR) @endwise.error)

((MISSING) @endwise.missing)
