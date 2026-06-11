; Liquid closes block tags with {% end<tag> %}. Every "%}" token of the
; construct is a cursor anchor: the closer's own "%}" yields a candidate
; whose construct ends on the cursor row, which the client treats as closed.

((if_statement "%}" @endwise.cursor) @endwise
  (#set! endwise "{% endif %}"))

((unless_statement "%}" @endwise.cursor) @endwise
  (#set! endwise "{% endunless %}"))

((for_loop_statement "%}" @endwise.cursor) @endwise
  (#set! endwise "{% endfor %}"))

((case_statement "%}" @endwise.cursor) @endwise
  (#set! endwise "{% endcase %}"))

((capture_statement "%}" @endwise.cursor) @endwise
  (#set! endwise "{% endcapture %}"))

((ERROR ("if" . (_) @endwise.cursor . "%}"? @endwise.cursor))
  (#set! endwise "{% endif %}"))

((ERROR ("unless" . (_) @endwise.cursor . "%}"? @endwise.cursor))
  (#set! endwise "{% endunless %}"))

((ERROR ("for" . (_) iterator: (_) @endwise.cursor . "%}"? @endwise.cursor))
  (#set! endwise "{% endfor %}"))

((ERROR ("case" . (_) @endwise.cursor . "%}"? @endwise.cursor))
  (#set! endwise "{% endcase %}"))

((ERROR ("capture" . (_) @endwise.cursor . "%}"? @endwise.cursor))
  (#set! endwise "{% endcapture %}"))

((ERROR) @endwise.error)

((MISSING) @endwise.missing)
