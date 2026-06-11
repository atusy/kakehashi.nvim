; tree-sitter-zsh derives from tree-sitter-bash, so this mirrors
; queries/bash/endwise.scm.

((if_statement "then" @endwise.cursor) @endwise
  (#set! endwise "fi"))

((do_group "do" @endwise.cursor) @endwise
  (#set! endwise "done"))

((case_statement "in" @endwise.cursor) @endwise
  (#set! endwise "esac"))

; no anchor before "then"/"in": a ";" or newline token may sit in between
((ERROR ("if" . (_) "then" @endwise.cursor))
  (#set! endwise "fi"))

((ERROR ("do" @endwise.cursor))
  (#set! endwise "done"))

((ERROR ("case" . (_) "in" @endwise.cursor))
  (#set! endwise "esac"))

((ERROR) @endwise.error)

((MISSING) @endwise.missing)
