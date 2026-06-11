; Derived from nvim-treesitter-endwise (MIT) queries/lua/endwise.scm,
; reformulated for kakehashi: #set! metadata instead of the #endwise!
; directive, plus error/missing evidence captures for the client heuristic.

((function_declaration parameters: (_) @endwise.cursor) @endwise
  (#set! endwise "end"))

((function_definition parameters: (_) @endwise.cursor) @endwise
  (#set! endwise "end"))

((while_statement "do" @endwise.cursor) @endwise
  (#set! endwise "end"))

((for_statement "do" @endwise.cursor) @endwise
  (#set! endwise "end"))

((if_statement "then" @endwise.cursor) @endwise
  (#set! endwise "end"))

((do_statement "do" @endwise.cursor) @endwise
  (#set! endwise "end"))

((ERROR ("function" . (_)? . (parameters) @endwise.cursor))
  (#set! endwise "end"))

((ERROR ("do" @endwise.cursor))
  (#set! endwise "end"))

((ERROR ("while" . (_) . "do" @endwise.cursor))
  (#set! endwise "end"))

((ERROR ("for" . [(for_generic_clause) (for_numeric_clause)] . "do" @endwise.cursor))
  (#set! endwise "end"))

((ERROR ("if" . (_) . "then" @endwise.cursor))
  (#set! endwise "end"))

((ERROR) @endwise.error)

((MISSING) @endwise.missing)
