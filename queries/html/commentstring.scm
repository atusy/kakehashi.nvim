((document) @commentstring
  (#set! commentstring "<!-- %s -->"))

((style_element) @commentstring
  (#set! commentstring "/* %s */"))

((script_element) @commentstring
  (#set! commentstring "// %s"))
