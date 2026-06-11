; Fortran closes each construct with a dedicated "end <keyword>" statement.
; Unclosed inner constructs steal the enclosing "end program"/"end module"
; line as their own end statement, which is exactly the indent-mismatch
; shape the client heuristic detects.

((if_statement "then" @endwise.cursor) @endwise
  (#set! endwise "end if"))

((do_loop (do_statement) @endwise.cursor) @endwise
  (#set! endwise "end do"))

((select_case_statement (selector) @endwise.cursor) @endwise
  (#set! endwise "end select"))

((where_statement (parenthesized_expression) @endwise.cursor) @endwise
  (#set! endwise "end where"))

((forall_statement (triplet_spec) @endwise.cursor) @endwise
  (#set! endwise "end forall"))

((associate_statement (association_list) @endwise.cursor) @endwise
  (#set! endwise "end associate"))

((program (program_statement) @endwise.cursor) @endwise
  (#set! endwise "end program"))

((module (module_statement) @endwise.cursor) @endwise
  (#set! endwise "end module"))

((subroutine (subroutine_statement) @endwise.cursor) @endwise
  (#set! endwise "end subroutine"))

((function (function_statement) @endwise.cursor) @endwise
  (#set! endwise "end function"))

((derived_type_definition (derived_type_statement) @endwise.cursor) @endwise
  (#set! endwise "end type"))

((interface (interface_statement) @endwise.cursor) @endwise
  (#set! endwise "end interface"))

((ERROR (program_statement) @endwise.cursor)
  (#set! endwise "end program"))

((ERROR (module_statement) @endwise.cursor)
  (#set! endwise "end module"))

((ERROR (subroutine_statement) @endwise.cursor)
  (#set! endwise "end subroutine"))

((ERROR (function_statement) @endwise.cursor)
  (#set! endwise "end function"))

((ERROR (derived_type_statement) @endwise.cursor)
  (#set! endwise "end type"))

((ERROR (interface_statement) @endwise.cursor)
  (#set! endwise "end interface"))

((ERROR) @endwise.error)

((MISSING) @endwise.missing)
