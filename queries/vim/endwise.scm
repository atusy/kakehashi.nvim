; Derived from nvim-treesitter-endwise (MIT) queries/vim/endwise.scm.

((if_statement condition: (_) @endwise.cursor) @endwise
  (#set! endwise "endif"))

((for_loop iter: (_) @endwise.cursor)
  (#set! endwise "endfor"))

((while_loop condition: (_) @endwise.cursor)
  (#set! endwise "endwhile"))

((function_definition
   "function"
   (function_declaration parameters: (_) @endwise.cursor)
   .
   ["abort" "closure" "dict" "range"]* @endwise.cursor) @endwise
  (#set! endwise "endfunction"))

((try_statement "try" @endwise.cursor) @endwise
  (#set! endwise "endtry"))

((ERROR ("if" . (_) @endwise.cursor))
  (#set! endwise "endif"))

((ERROR ("for" . (_) . "in" . (_) @endwise.cursor))
  (#set! endwise "endfor"))

((ERROR ("while" . (_) @endwise.cursor))
  (#set! endwise "endwhile"))

((ERROR ("function"
          (bang)?
          .
          (function_declaration parameters: (_) @endwise.cursor)
          ["abort" "closure" "dict" "range"]* @endwise.cursor))
  (#set! endwise "endfunction"))

((ERROR ("try" @endwise.cursor))
  (#set! endwise "endtry"))

((ERROR) @endwise.error)

((MISSING) @endwise.missing)
