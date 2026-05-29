(** Pattern-match exhaustiveness and redundancy checking (Maranget's usefulness
    algorithm). See [docs/04-exhaustiveness.md]. *)

type result =
  { exhaustive : bool
  ; witness : Ast.pat option (** a counterexample pattern, when not exhaustive *)
  ; redundant : int list (** indices (0-based) of unreachable clauses *)
  }

(** [check denv cases] reports whether the clause patterns cover all values, a
    witness for an uncovered case if not, and any redundant clauses. The
    scrutinee's type is recovered from the constructors present plus [denv]. *)
val check : Types.denv -> Ast.case list -> result
