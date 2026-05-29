(** Hindley-Milner type inference (Algorithm W) with Rémy-style levels.

    Inference is destructive: unification mutates the [TVar] union-find in place,
    and a global {e level} counter tracks how deeply nested in [let] bindings we
    are. {!generalize} quantifies exactly the variables whose level exceeds the
    current one, which is what makes [let]-polymorphism sound and cheap (no
    scanning the whole environment). The value restriction governs whether a
    [let] right-hand side may generalize. See [docs/03-type-inference.md]. *)

(** A type clash, with the source span of the offending expression. *)
exception Type_error of Span.t * string

(** An infinite type (the occurs check failed), e.g. inferring [x x]. *)
exception Occurs_check of Span.t * string

(** A non-fatal diagnostic (e.g. a non-exhaustive match), accumulated during
    inference and drained by {!get_warnings}. *)
type warning =
  { wspan : Span.t
  ; wmsg : string
  }

(** Warnings emitted since the last {!clear_warnings}, in source order. *)
val get_warnings : unit -> warning list

val clear_warnings : unit -> unit

(** Reset all inference state (level counter, fresh-variable ids, warnings) — call
    once per program for deterministic output. *)
val reset : unit -> unit

(** Infer the principal type scheme of a single closed expression. *)
val infer_scheme : Types.denv -> Env.t -> Ast.expr -> Types.scheme

(** Infer a top-level [let]/[let rec] group, returning the environment extended
    with the generalized bindings. *)
val infer_decl : Types.denv -> Env.t -> bool -> Ast.binding list -> Env.t

(** Elaborate a whole program: register type declarations, then thread the
    environment through the [let] declarations in order. Returns the declaration
    environment and the inferred scheme of each top-level binding. *)
val infer_program : Ast.program -> Types.denv * (string * Types.scheme) list
