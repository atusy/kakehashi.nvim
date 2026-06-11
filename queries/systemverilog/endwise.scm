; SystemVerilog pairs each opener with a dedicated closer (begin/end,
; module/endmodule, ...). The parser reports unclosed constructs with a
; MISSING closer inside them, so construct patterns carry most cases.

((seq_block "begin" @endwise.cursor) @endwise
  (#set! endwise "end"))

((module_declaration [(module_ansi_header) (module_nonansi_header)] @endwise.cursor) @endwise
  (#set! endwise "endmodule"))

((class_declaration ";" @endwise.cursor) @endwise
  (#set! endwise "endclass"))

((function_declaration (function_body_declaration ";" @endwise.cursor)) @endwise
  (#set! endwise "endfunction"))

((task_declaration (task_body_declaration ";" @endwise.cursor)) @endwise
  (#set! endwise "endtask"))

((package_declaration ";" @endwise.cursor) @endwise
  (#set! endwise "endpackage"))

((interface_declaration [(interface_ansi_header) (interface_nonansi_header)] @endwise.cursor) @endwise
  (#set! endwise "endinterface"))

((case_statement (case_expression) @endwise.cursor . ")" @endwise.cursor) @endwise
  (#set! endwise "endcase"))

((generate_region "generate" @endwise.cursor) @endwise
  (#set! endwise "endgenerate"))

((ERROR ("begin" @endwise.cursor))
  (#set! endwise "end"))

((ERROR (module_ansi_header) @endwise.cursor)
  (#set! endwise "endmodule"))

((ERROR ("case" . "(" . (case_expression) @endwise.cursor . ")" @endwise.cursor))
  (#set! endwise "endcase"))

((ERROR ("generate" @endwise.cursor))
  (#set! endwise "endgenerate"))

((ERROR) @endwise.error)

((MISSING) @endwise.missing)
