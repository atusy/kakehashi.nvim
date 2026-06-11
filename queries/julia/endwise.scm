; Derived from nvim-treesitter-endwise (MIT) queries/julia/endwise.scm.

((module_definition name: (_) @endwise.cursor) @endwise
  (#set! endwise "end"))

((struct_definition (type_head) @endwise.cursor) @endwise
  (#set! endwise "end"))

((quote_statement "quote" @endwise.cursor) @endwise
  (#set! endwise "end"))

((if_statement condition: (_) @endwise.cursor) @endwise
  (#set! endwise "end"))

((try_statement "try" @endwise.cursor) @endwise
  (#set! endwise "end"))

((for_statement . (for_binding)* . (for_binding) @endwise.cursor) @endwise
  (#set! endwise "end"))

((while_statement condition: (_) @endwise.cursor) @endwise
  (#set! endwise "end"))

((let_statement "let" @endwise.cursor [(identifier) (assignment)]? @endwise.cursor) @endwise
  (#set! endwise "end"))

((function_definition
   (signature [(identifier) (call_expression) (typed_expression) (where_expression)] @endwise.cursor)) @endwise
  (#set! endwise "end"))

; anonymous function
((function_definition
   (signature (argument_list) @endwise.cursor (where_expression)? @endwise.cursor)) @endwise
  (#set! endwise "end"))

((macro_definition (signature [(identifier) (call_expression)]) @endwise.cursor) @endwise
  (#set! endwise "end"))

((do_clause ["do" (argument_list)] @endwise.cursor) @endwise
  (#set! endwise "end"))

((compound_statement "begin" @endwise.cursor) @endwise
  (#set! endwise "end"))

((ERROR ["module" "baremodule"] . (_) @endwise.cursor)
  (#set! endwise "end"))

((ERROR "mutable"? "struct" . (type_head) @endwise.cursor)
  (#set! endwise "end"))

((ERROR "quote" @endwise.cursor)
  (#set! endwise "end"))

((ERROR "if" . (_) @endwise.cursor)
  (#set! endwise "end"))

((ERROR "try" @endwise.cursor)
  (#set! endwise "end"))

((ERROR "for" . (for_binding)* . (for_binding) @endwise.cursor)
  (#set! endwise "end"))

((ERROR "while" . (_) @endwise.cursor)
  (#set! endwise "end"))

((ERROR "let" @endwise.cursor [(identifier) (assignment)]? @endwise.cursor)
  (#set! endwise "end"))

((ERROR "function"
   . (signature [(identifier) (call_expression) (typed_expression) (where_expression)] @endwise.cursor))
  (#set! endwise "end"))

((ERROR "function" . (signature (argument_list) @endwise.cursor (where_expression)? @endwise.cursor))
  (#set! endwise "end"))

((ERROR "macro" . (signature [(identifier) (call_expression)]) @endwise.cursor)
  (#set! endwise "end"))

((ERROR ["do" (argument_list)] @endwise.cursor)
  (#set! endwise "end"))

((ERROR "begin" @endwise.cursor)
  (#set! endwise "end"))

((ERROR) @endwise.error)

((MISSING) @endwise.missing)
