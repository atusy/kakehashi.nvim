; MATLAB closes every block with "end". Functions may legally omit it in
; script files — harmless here, since a construct only gains an end when
; the client heuristic sees parse-error evidence.

((if_statement condition: (_) @endwise.cursor) @endwise
  (#set! endwise "end"))

((for_statement (iterator) @endwise.cursor) @endwise
  (#set! endwise "end"))

((while_statement condition: (_) @endwise.cursor) @endwise
  (#set! endwise "end"))

((switch_statement condition: (_) @endwise.cursor) @endwise
  (#set! endwise "end"))

((try_statement "try" @endwise.cursor) @endwise
  (#set! endwise "end"))

((function_definition name: (_) @endwise.cursor (function_arguments)? @endwise.cursor) @endwise
  (#set! endwise "end"))

((class_definition name: (_) @endwise.cursor) @endwise
  (#set! endwise "end"))

((ERROR ("if" . (_) @endwise.cursor))
  (#set! endwise "end"))

((ERROR (["for" "parfor"] . (iterator) @endwise.cursor))
  (#set! endwise "end"))

((ERROR ("while" . (_) @endwise.cursor))
  (#set! endwise "end"))

((ERROR ("switch" . (_) @endwise.cursor))
  (#set! endwise "end"))

((ERROR ("try" @endwise.cursor))
  (#set! endwise "end"))

((ERROR ("function" . (function_output)? . (identifier) @endwise.cursor . (function_arguments)? @endwise.cursor))
  (#set! endwise "end"))

((ERROR ("classdef" . (identifier) @endwise.cursor))
  (#set! endwise "end"))

((ERROR) @endwise.error)

((MISSING) @endwise.missing)
