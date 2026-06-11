; Erlang closes case/if/receive/begin/fun/try/maybe expressions with "end".
; The grammar recovers an unclosed construct as the construct itself plus a
; (MISSING "end") inside it, so construct patterns carry most of the weight.

((case_expr "case" @endwise.cursor "of" @endwise.cursor) @endwise
  (#set! endwise "end"))

((if_expr "if" @endwise.cursor) @endwise
  (#set! endwise "end"))

((receive_expr "receive" @endwise.cursor) @endwise
  (#set! endwise "end"))

((block_expr "begin" @endwise.cursor) @endwise
  (#set! endwise "end"))

((anonymous_fun "fun" @endwise.cursor (fun_clause (clause_body . "->" @endwise.cursor))?) @endwise
  (#set! endwise "end"))

((try_expr "try" @endwise.cursor) @endwise
  (#set! endwise "end"))

((maybe_expr "maybe" @endwise.cursor) @endwise
  (#set! endwise "end"))

((ERROR ("case" . (_) . "of" @endwise.cursor))
  (#set! endwise "end"))

((ERROR ("if" @endwise.cursor))
  (#set! endwise "end"))

((ERROR ("receive" @endwise.cursor))
  (#set! endwise "end"))

((ERROR ("begin" @endwise.cursor))
  (#set! endwise "end"))

((ERROR ("fun" . (expr_args) @endwise.cursor . "->"? @endwise.cursor))
  (#set! endwise "end"))

((ERROR ("try" @endwise.cursor))
  (#set! endwise "end"))

((ERROR ("maybe" @endwise.cursor))
  (#set! endwise "end"))

((ERROR) @endwise.error)

((MISSING) @endwise.missing)
