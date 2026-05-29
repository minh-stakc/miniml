(** Decision-tree pattern-match compilation (Maranget, "Compiling Pattern
    Matching to Good Decision Trees", ML 2008).

    The naive strategy in {!Compile} tests each clause independently, so clauses
    that share an outer constructor re-examine it. {!build} instead compiles the
    whole clause matrix into a {b decision tree}: each sub-value — an {e occurrence},
    addressed by a path from the scrutinee ([int list]) — is tested at most once
    on any path, and clauses branch only on what differs.

    The tree is built purely over patterns (no runtime values) and lowered to
    bytecode by {!Compile.tree_match}. See [docs/09-decision-trees.md]. *)

type tree =
  | Leaf of int * (string * int list) list
  (** a clause body to run (by 0-based clause index) and the variables it
        binds, each paired with the occurrence path holding its value *)
  | Fail (** no clause matches: a runtime match failure *)
  | Switch of int list * (Bytecode.test * tree) list * tree option
  (** test the value at this occurrence; branch by constructor; the optional
        default is omitted exactly when the tested constructors are complete *)

(** [build clauses] compiles [(pattern, clause_index)] pairs, in priority order,
    into a decision tree. *)
val build : (Ast.pat * int) list -> tree
