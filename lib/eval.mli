(** A small big-step reference interpreter — the {e oracle} for differential
    testing. It evaluates the surface AST directly (no compilation), so any
    disagreement with the {!Vm} pins the bug to the compiler or VM rather than to
    a shared front end. *)

(** Raised on a genuinely partial pattern match. Other runtime mishaps cannot
    occur on well-typed input. *)
exception Runtime_error of string

(** Evaluate a closed expression in the empty environment. *)
val run : Ast.expr -> Value.t

(** A binary primitive, exposed so the VM and the evaluator share one definition
    of arithmetic, comparison, and structural equality. *)
val eval_binop : Ast.binop -> Value.t -> Value.t -> Value.t

(** Run a whole program, returning the final environment as
    [(name, value)] bindings in scope. *)
val eval_program : Ast.program -> (string * Value.t) list
