(** The bytecode stack machine.

    A register holds the current environment ([Value.t list], indexed by de Bruijn
    position); an operand stack holds intermediate values; a return stack holds
    call frames. [APPLY] pushes a frame and [RETURN] pops one, while [TAILAPPLY]
    reuses the current frame — so deep tail recursion runs in constant space. The
    main loop is a single iterative [match] over the instruction at [pc]. See
    [docs/05-bytecode-vm.md]. *)

(** A trap that should be {e unreachable} on well-typed input — applying a
    non-function, projecting a non-record, and so on. Reaching it would indicate a
    soundness bug, so the differential and property tests assert it never fires. *)
exception Type_trap of string

(** The deepest the return stack grew during the last {!run} — a witness, used by
    tests, that tail calls do not grow the stack. *)
val max_frame_depth : int ref

(** Execute an assembled bytecode program; the result is the value left on top of
    the stack at [STOP]. *)
val run : Bytecode.code -> Value.t

(** Compile a closed expression and run it. *)
val run_expr : Ast.expr -> Value.t
