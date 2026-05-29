(** Pretty-printers for the surface AST, inferred types, and type schemes.

    All printers are precedence-aware (minimal parentheses). Type printers rename
    variables to ['a], ['b], … in order of first appearance, so output is stable
    regardless of internal variable ids. *)

(** Print a surface expression. *)
val expr : Ast.expr -> string

(** Print a pattern (also used to render exhaustiveness-check witnesses). *)
val pat : Ast.pat -> string

(** Print a whole program (one declaration per line). *)
val program : Ast.program -> string

(** Print an inferred monotype, e.g. ["('a -> 'b) -> 'a list -> 'b list"]. *)
val typ : Types.typ -> string

(** Print a type scheme (its quantified variables appear as ['a], ['b], …). *)
val scheme : Types.scheme -> string
