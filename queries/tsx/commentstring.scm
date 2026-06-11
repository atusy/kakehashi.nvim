((program) @commentstring
  (#set! commentstring "// %s"))

; jsx bodies (fragments parse as jsx_element too) comment as
; expressions wrapped in braces...
((jsx_element) @commentstring
  (#set! commentstring "{/* %s */}"))

; ...but attribute positions and embedded expressions are plain typescript
((jsx_attribute) @commentstring
  (#set! commentstring "// %s"))

((jsx_expression) @commentstring
  (#set! commentstring "// %s"))

((comment) @commentstring
  (#set! commentstring "// %s"))
