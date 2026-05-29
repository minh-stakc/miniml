(** Runtime values, shared by the reference evaluator ({!Eval}) and the bytecode
    VM ({!Vm}). One representation lets a single structural {!equal} drive
    differential testing. Constructors carry their name (not an integer tag) so
    values print readably; lists and records have dedicated cases. *)

type t =
  | VInt of int
  | VBool of bool
  | VUnit
  | VTuple of t list
  | VList of t list
  | VData of string * t option (** constructor name + optional argument *)
  | VClosEval of eval_closure (** a closure produced by the evaluator *)
  | VClosVM of vm_closure (** a closure produced by the VM *)
  | VRef of t ref (** a mutable reference cell *)
  | VRecord of (string * t) list (** a record: field name -> value *)

and eval_closure =
  { param : string
  ; cbody : Ast.expr
  ; mutable eenv : (string * t) list (** mutable for let-rec knot-tying *)
  }

and vm_closure =
  { code : int (** entry program-counter into the bytecode *)
  ; mutable venv : t list (** captured environment; mutable for let-rec *)
  }

(** Structural equality. Records compare order-independently; closures are opaque
    (never equal), so differential tests compare first-order results. *)
val equal : t -> t -> bool

(** Render a value for the REPL (closures print as [<fun>]). *)
val to_string : t -> string
