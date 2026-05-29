(** Lowering the surface AST to {!Bytecode}.

    Variables are resolved to de Bruijn indices against a compile-time name stack,
    so the VM never does a name lookup. Tail position is threaded through [if],
    [match] arms, and [let] bodies so calls in tail position emit [TAILAPPLY]
    (constant stack). Pattern matching can be compiled by either strategy below;
    a two-pass assembler then resolves label ids to addresses. See
    [docs/05-bytecode-vm.md] and [docs/09-decision-trees.md]. *)

(** How [match] is compiled. Both produce equivalent code; the default is the
    optimizing one. Selectable mainly so tests can check the two agree. *)
type strategy =
  | Naive (** test each clause in turn *)
  | Decision_tree (** Maranget decision tree: each occurrence tested at most once *)

(** The match-compilation strategy in effect (default {!Decision_tree}). *)
val strategy : strategy ref

(** Compile a closed expression to an assembled, runnable bytecode program. *)
val compile_expr : Ast.expr -> Bytecode.code
