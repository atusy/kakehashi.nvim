; CMake closes every block with a dedicated keyword that must carry its own
; argument list: if()/endif(), foreach()/endforeach(), and so on.

((if_condition (if_command) @endwise.cursor) @endwise
  (#set! endwise "endif()"))

((foreach_loop (foreach_command) @endwise.cursor) @endwise
  (#set! endwise "endforeach()"))

((while_loop (while_command) @endwise.cursor) @endwise
  (#set! endwise "endwhile()"))

((function_def (function_command) @endwise.cursor) @endwise
  (#set! endwise "endfunction()"))

((macro_def (macro_command) @endwise.cursor) @endwise
  (#set! endwise "endmacro()"))

((block_def (block_command) @endwise.cursor) @endwise
  (#set! endwise "endblock()"))

((ERROR (if_command) @endwise.cursor)
  (#set! endwise "endif()"))

((ERROR (foreach_command) @endwise.cursor)
  (#set! endwise "endforeach()"))

((ERROR (while_command) @endwise.cursor)
  (#set! endwise "endwhile()"))

((ERROR (function_command) @endwise.cursor)
  (#set! endwise "endfunction()"))

((ERROR (macro_command) @endwise.cursor)
  (#set! endwise "endmacro()"))

((ERROR (block_command) @endwise.cursor)
  (#set! endwise "endblock()"))

((ERROR) @endwise.error)

((MISSING) @endwise.missing)
