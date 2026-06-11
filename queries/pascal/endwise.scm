; Pascal closes begin/case/record/class blocks with "end". Inserted bare —
; "end;" would be a syntax error before "else", and the parser only ever
; reports (MISSING kEnd); punctuation stays with the user.

((block (kBegin) @endwise.cursor) @endwise
  (#set! endwise "end"))

((case (kOf) @endwise.cursor) @endwise
  (#set! endwise "end"))

((declClass [(kRecord) (kClass) (kObject)] @endwise.cursor) @endwise
  (#set! endwise "end"))

((ERROR (kBegin) @endwise.cursor)
  (#set! endwise "end"))

((ERROR (kCase) . (_) . (kOf) @endwise.cursor)
  (#set! endwise "end"))

((ERROR [(kRecord) (kClass) (kObject)] @endwise.cursor)
  (#set! endwise "end"))

((ERROR) @endwise.error)

((MISSING) @endwise.missing)
