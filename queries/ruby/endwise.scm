; Derived from nvim-treesitter-endwise (MIT) queries/ruby/endwise.scm.
; The heredoc rule is not ported: it needs the upstream suffix machinery.

((module name: (_) @endwise.cursor) @endwise
  (#set! endwise "end"))

((class name: (_) @endwise.cursor superclass: (_)? @endwise.cursor) @endwise
  (#set! endwise "end"))

((singleton_class "class" . "<<" . value: (_) @endwise.cursor) @endwise
  (#set! endwise "end"))

((method name: (_) @endwise.cursor parameters: (_)? @endwise.cursor) @endwise
  (#set! endwise "end"))

((singleton_method name: (_) @endwise.cursor parameters: (_)? @endwise.cursor) @endwise
  (#set! endwise "end"))

((while condition: (_) @endwise.cursor body: (do ("do")? @endwise.cursor) @endwise)
  (#set! endwise "end"))

((until condition: (_) @endwise.cursor body: (do ("do")? @endwise.cursor) @endwise)
  (#set! endwise "end"))

((for value: (_) @endwise.cursor body: (do ("do")? @endwise.cursor) @endwise)
  (#set! endwise "end"))

((do_block "do" @endwise.cursor parameters: (_)? @endwise.cursor) @endwise
  (#set! endwise "end"))

((if condition: (_) @endwise.cursor) @endwise
  (#set! endwise "end"))

((begin
   "begin" @endwise.cursor
   .
   (rescue "rescue" @endwise.cursor exceptions: (_)? @endwise.cursor)?
   .
   (ensure "ensure" @endwise.cursor)?) @endwise
  (#set! endwise "end"))

((unless condition: (_) @endwise.cursor) @endwise
  (#set! endwise "end"))

((case value: (_) @endwise.cursor) @endwise
  (#set! endwise "end"))

((case) @endwise.cursor @endwise
  (#set! endwise "end"))

((ERROR ("module" . [(constant) (scope_resolution)] @endwise.cursor))
  (#set! endwise "end"))

((ERROR ("class" . [(constant) (scope_resolution)] @endwise.cursor . (superclass)? @endwise.cursor))
  (#set! endwise "end"))

((ERROR ("class" . "<<" . (_) @endwise.cursor))
  (#set! endwise "end"))

((ERROR ("def" . (identifier) @endwise.cursor . (method_parameters)? @endwise.cursor))
  (#set! endwise "end"))

((ERROR ("def" . (identifier) . "." . (identifier) @endwise.cursor . (method_parameters)? @endwise.cursor))
  (#set! endwise "end"))

((ERROR ("while" . (_) @endwise.cursor . "do"? @endwise.cursor))
  (#set! endwise "end"))

((ERROR ("until" . (_) @endwise.cursor . "do"? @endwise.cursor))
  (#set! endwise "end"))

((ERROR ("for" . (_) . (in . "in" . (_) @endwise.cursor) . "do"? @endwise.cursor))
  (#set! endwise "end"))

((ERROR ("do" @endwise.cursor . (block_parameters)? @endwise.cursor))
  (#set! endwise "end"))

((ERROR ("begin" @endwise.cursor
          .
          ["rescue" @endwise.cursor (rescue "rescue" @endwise.cursor exceptions: (_)? @endwise.cursor)]?
          .
          ["ensure" (ensure "ensure" @endwise.cursor)]?))
  (#set! endwise "end"))

((ERROR ("if" . (_) @endwise.cursor . (then)? @endwise.cursor))
  (#set! endwise "end"))

((ERROR ("unless" . (_) @endwise.cursor . (then)? @endwise.cursor))
  (#set! endwise "end"))

((ERROR) @endwise.error)

((MISSING) @endwise.missing)
