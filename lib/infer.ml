(** Hindley-Milner type inference — Algorithm W with Rémy-style levels.

    The four moving parts:
    - {b unify} makes two types equal by mutating type variables, running the
      {b occurs check} (rejecting infinite types) and {b lowering levels} as it
      links variables;
    - {b generalize} turns a monotype into a polymorphic scheme by quantifying
      the variables created {e inside} the current [let] (those with level
      strictly greater than the surrounding level);
    - {b instantiate} replaces a scheme's quantified variables with fresh ones at
      each use;
    - the {b value restriction} only generalizes when the bound expression is a
      syntactic value, keeping inference sound in the presence of mutable state.

    See [docs/03-type-inference.md] for the full walkthrough and the worked
    adversarial examples. *)

open Types

exception Type_error of Span.t * string
exception Occurs_check of Span.t * string

(* ------------------------------------------------------------------ *)
(* Levels *)

(* The level of the context we are currently elaborating. Incremented on entry
   to a [let] right-hand side, decremented on the way out. A variable born at
   level n "belongs to" the n-th enclosing let-rhs. *)
let current_level = ref 0
let enter_level () = incr current_level
let leave_level () = decr current_level

let reset () =
  current_level := 0;
  reset_counter ()
;;

(* ------------------------------------------------------------------ *)
(* Unification *)

(* Internal exceptions, turned into user-facing errors (with a span) by [unify]. *)
exception Occurs_internal
exception Unify_internal

(* Occurs check AND level adjustment, in a single traversal of [t]:
   - if the variable [id] occurs in [t], the unification would build an infinite
     type (e.g. ['a = 'a -> 'b]) — reject it;
   - every unbound variable reachable from [t] has its level lowered to at most
     [lvl]. This is the subtle, load-bearing step: [id] is about to be linked to
     [t], so every variable in [t] becomes reachable from wherever [id] was, and
     must not be generalized at any level deeper than [id]'s. Forgetting this
     silently over-generalizes and makes inference unsound. *)
let rec occurs_adjust (id : int) (lvl : level) (t : typ) : unit =
  match repr t with
  | TVar ({ contents = Unbound (id', l') } as r) ->
    if id = id' then raise Occurs_internal;
    if l' > lvl then r := Unbound (id', lvl)
  | TVar { contents = Link _ } -> assert false (* repr removes links *)
  | TArrow (a, b) ->
    occurs_adjust id lvl a;
    occurs_adjust id lvl b
  | TTuple ts | TCon (_, ts) -> List.iter (occurs_adjust id lvl) ts
;;

let rec unify_ (t1 : typ) (t2 : typ) : unit =
  let t1 = repr t1
  and t2 = repr t2 in
  if t1 == t2
  then ()
  else (
    match t1, t2 with
    | TVar ({ contents = Unbound (id, lvl) } as r), t
    | t, TVar ({ contents = Unbound (id, lvl) } as r) ->
      occurs_adjust id lvl t;
      r := Link t
    | TArrow (a1, b1), TArrow (a2, b2) ->
      unify_ a1 a2;
      unify_ b1 b2
    | TTuple xs, TTuple ys when List.length xs = List.length ys -> List.iter2 unify_ xs ys
    | TCon (n1, a1), TCon (n2, a2) when n1 = n2 && List.length a1 = List.length a2 ->
      List.iter2 unify_ a1 a2
    | _ -> raise Unify_internal)
;;

(* Public entry point: attaches a source span to whatever goes wrong. *)
let unify ~(span : Span.t) (t1 : typ) (t2 : typ) : unit =
  try unify_ t1 t2 with
  | Occurs_internal ->
    raise
      (Occurs_check
         (span, Printf.sprintf "cannot construct the infinite type %s" (Pretty.typ t1)))
  | Unify_internal ->
    raise
      (Type_error
         ( span
         , Printf.sprintf
             "this expression has type %s but type %s was expected"
             (Pretty.typ t2)
             (Pretty.typ t1) ))
;;

(* ------------------------------------------------------------------ *)
(* Generalization and instantiation *)

(* Quantify every unbound variable whose level is strictly greater than the
   current level. Call this AFTER [leave_level], so "current level" is the level
   surrounding the let whose right-hand side we just elaborated. The strict [>]
   is essential: a variable at exactly the current level is reachable from the
   enclosing environment and must stay monomorphic. *)
let generalize (t : typ) : scheme =
  let acc = ref [] in
  let rec go t =
    match repr t with
    | TVar { contents = Unbound (id, lvl) } ->
      if lvl > !current_level && not (List.mem id !acc) then acc := id :: !acc
    | TVar { contents = Link _ } -> assert false
    | TArrow (a, b) ->
      go a;
      go b
    | TTuple ts | TCon (_, ts) -> List.iter go ts
  in
  go t;
  { qvars = List.rev !acc; body = t }
;;

(* A monomorphic "scheme": no quantification (used for lambda/pattern bindings
   and for the value restriction). *)
let dont_generalize (t : typ) : scheme = { qvars = []; body = t }

(* Replace the scheme's quantified variables with fresh variables at the current
   level. Non-quantified variables in the body are shared (returned as-is), so
   the scheme stays connected to the rest of the type graph. *)
let instantiate (s : scheme) : typ =
  match s.qvars with
  | [] -> s.body
  | qvars ->
    let tbl : (int, typ) Hashtbl.t = Hashtbl.create 8 in
    List.iter (fun id -> Hashtbl.replace tbl id (new_var !current_level)) qvars;
    let rec go t =
      match repr t with
      | TVar { contents = Unbound (id, _) } as v ->
        (match Hashtbl.find_opt tbl id with
         | Some fresh -> fresh
         | None -> v)
      | TVar { contents = Link _ } -> assert false
      | TArrow (a, b) -> TArrow (go a, go b)
      | TTuple ts -> TTuple (List.map go ts)
      | TCon (n, ts) -> TCon (n, List.map go ts)
    in
    go s.body
;;

(* ------------------------------------------------------------------ *)
(* The value restriction *)

(* Only syntactic values may have their types generalized. For the pure core
   this rarely changes what type-checks, but it is exactly the gate that keeps
   inference sound once mutable references are added (v1.0). *)
let rec is_value (e : Ast.expr) : bool =
  match e with
  | Ast.EVar _ | Ast.ELit _ | Ast.EFun _ | Ast.ENil _ -> true
  | Ast.ECtor (_, None, _) -> true
  | Ast.ECtor (_, Some e, _) -> is_value e
  | Ast.ETuple (es, _) -> List.for_all is_value es
  | Ast.ECons (h, t, _) -> is_value h && is_value t
  | _ -> false
;;

(* ------------------------------------------------------------------ *)
(* Turning a written type expression into a monotype *)

(* Used to type constructor uses: [subst] maps the ADT's type-parameter names to
   fresh variables, so each use of a constructor is independently polymorphic. *)
let rec typ_of_ty_expr (subst : (string * typ) list) (te : Ast.ty_expr) : typ =
  match te with
  | Ast.TyVar a ->
    (match List.assoc_opt a subst with
     | Some t -> t
     | None ->
       raise (Type_error (Span.dummy, Printf.sprintf "unbound type variable '%s" a)))
  | Ast.TyCon (name, args) -> TCon (name, List.map (typ_of_ty_expr subst) args)
  | Ast.TyArrow (a, b) -> TArrow (typ_of_ty_expr subst a, typ_of_ty_expr subst b)
  | Ast.TyTuple ts -> TTuple (List.map (typ_of_ty_expr subst) ts)
;;

(* ------------------------------------------------------------------ *)
(* Inference *)

let lambdas (params : string list) (body : Ast.expr) : Ast.expr =
  List.fold_right (fun p acc -> Ast.EFun (p, acc, Ast.span_of_expr body)) params body
;;

let rec infer (denv : denv) (env : Env.t) (e : Ast.expr) : typ =
  match e with
  | Ast.ELit (Ast.LInt _, _) -> t_int
  | Ast.ELit (Ast.LBool _, _) -> t_bool
  | Ast.ELit (Ast.LUnit, _) -> t_unit
  | Ast.EVar (x, sp) ->
    (match Env.find x env with
     | Some s -> instantiate s
     | None -> raise (Type_error (sp, "unbound variable " ^ x)))
  | Ast.EFun (x, body, _) ->
    (* A lambda parameter is monomorphic within the body. *)
    let tx = new_var !current_level in
    let tbody = infer denv (Env.add x (dont_generalize tx) env) body in
    TArrow (tx, tbody)
  | Ast.EApp (f, a, sp) ->
    let tf = infer denv env f in
    let ta = infer denv env a in
    let tr = new_var !current_level in
    unify ~span:sp tf (TArrow (ta, tr));
    tr
  | Ast.EIf (c, t, e, sp) ->
    unify ~span:(Ast.span_of_expr c) (infer denv env c) t_bool;
    let tt = infer denv env t in
    let te = infer denv env e in
    unify ~span:sp tt te;
    tt
  | Ast.ELet (is_rec, bs, body, _) ->
    let env' = infer_bindings denv env is_rec bs in
    infer denv env' body
  | Ast.ETuple (es, _) -> TTuple (List.map (infer denv env) es)
  | Ast.ENil _ -> t_list (new_var !current_level)
  | Ast.ECons (h, t, sp) ->
    let th = infer denv env h in
    let tt = infer denv env t in
    unify ~span:sp tt (t_list th);
    t_list th
  | Ast.ECtor (c, arg, sp) -> infer_ctor denv env c arg sp
  | Ast.EMatch (scrut, cases, _sp) ->
    (* [_sp] becomes the exhaustiveness-check site in v0.3. *)
    let tscrut = infer denv env scrut in
    let tresult = new_var !current_level in
    List.iter
      (fun (case : Ast.case) ->
         let tpat, binds = infer_pat denv case.lhs in
         unify ~span:(Ast.span_of_pat case.lhs) tpat tscrut;
         let env' =
           List.fold_left (fun g (n, t) -> Env.add n (dont_generalize t) g) env binds
         in
         let trhs = infer denv env' case.rhs in
         unify ~span:(Ast.span_of_expr case.rhs) trhs tresult)
      cases;
    tresult
  | Ast.EBinop (op, a, b, sp) ->
    let ta = infer denv env a
    and tb = infer denv env b in
    (match op with
     | Ast.Add | Ast.Sub | Ast.Mul | Ast.Div ->
       unify ~span:sp ta t_int;
       unify ~span:sp tb t_int;
       t_int
     | Ast.Lt | Ast.Le | Ast.Gt | Ast.Ge ->
       unify ~span:sp ta t_int;
       unify ~span:sp tb t_int;
       t_bool
     | Ast.And | Ast.Or ->
       unify ~span:sp ta t_bool;
       unify ~span:sp tb t_bool;
       t_bool
     | Ast.Eq | Ast.Neq ->
       (* structural equality at a single, shared type *)
       unify ~span:sp ta tb;
       t_bool)
  | Ast.EUnop (Ast.Neg, a, sp) ->
    unify ~span:sp (infer denv env a) t_int;
    t_int
  | Ast.EUnop (Ast.Not, a, sp) ->
    unify ~span:sp (infer denv env a) t_bool;
    t_bool
  | Ast.ESeq (a, b, _) ->
    (* sequencing: the first expression's value is discarded *)
    ignore (infer denv env a);
    infer denv env b

and infer_ctor denv env (c : string) (arg : Ast.expr option) (sp : Span.t) : typ =
  match Hashtbl.find_opt denv.ctors c with
  | None -> raise (Type_error (sp, "unknown constructor " ^ c))
  | Some ci ->
    let subst = List.map (fun p -> p, new_var !current_level) ci.ci_tparams in
    let result_ty = TCon (ci.ci_type, List.map snd subst) in
    (match ci.ci_arg, arg with
     | None, None -> result_ty
     | Some argte, Some ae ->
       let expected = typ_of_ty_expr subst argte in
       let actual = infer denv env ae in
       unify ~span:sp actual expected;
       result_ty
     | None, Some _ -> raise (Type_error (sp, c ^ " takes no argument"))
     | Some _, None -> raise (Type_error (sp, c ^ " expects an argument")))

(* Infer a pattern's type together with the (monomorphic) variables it binds. *)
and infer_pat (denv : denv) (p : Ast.pat) : typ * (string * typ) list =
  match p with
  | Ast.PWild _ -> new_var !current_level, []
  | Ast.PVar (x, _) ->
    let t = new_var !current_level in
    t, [ x, t ]
  | Ast.PLit (Ast.LInt _, _) -> t_int, []
  | Ast.PLit (Ast.LBool _, _) -> t_bool, []
  | Ast.PLit (Ast.LUnit, _) -> t_unit, []
  | Ast.PNil _ -> t_list (new_var !current_level), []
  | Ast.PCons (h, t, sp) ->
    let th, bh = infer_pat denv h in
    let tt, bt = infer_pat denv t in
    unify ~span:sp tt (t_list th);
    t_list th, bh @ bt
  | Ast.PTuple (ps, _) ->
    let results = List.map (infer_pat denv) ps in
    TTuple (List.map fst results), List.concat_map snd results
  | Ast.PCtor (c, arg, sp) ->
    (match Hashtbl.find_opt denv.ctors c with
     | None -> raise (Type_error (sp, "unknown constructor " ^ c))
     | Some ci ->
       let subst = List.map (fun p -> p, new_var !current_level) ci.ci_tparams in
       let result_ty = TCon (ci.ci_type, List.map snd subst) in
       (match ci.ci_arg, arg with
        | None, None -> result_ty, []
        | Some argte, Some ap ->
          let expected = typ_of_ty_expr subst argte in
          let tp, binds = infer_pat denv ap in
          unify ~span:sp tp expected;
          result_ty, binds
        | None, Some _ -> raise (Type_error (sp, c ^ " takes no argument"))
        | Some _, None -> raise (Type_error (sp, c ^ " expects an argument"))))

(* Elaborate a (possibly mutually recursive, possibly multi-binding) [let] and
   return the environment extended with the bound names. *)
and infer_bindings (denv : denv) (env : Env.t) (is_rec : bool) (bs : Ast.binding list)
  : Env.t
  =
  if not is_rec
  then (
    (* Non-recursive: each right-hand side is elaborated in the OUTER env, then
       generalized subject to the value restriction. *)
    let schemes =
      List.map
        (fun (b : Ast.binding) ->
           enter_level ();
           let rhs = lambdas b.params b.body in
           let t = infer denv env rhs in
           leave_level ();
           let s = if is_value rhs then generalize t else dont_generalize t in
           b.name, s)
        bs
    in
    List.fold_left (fun g (n, s) -> Env.add n s g) env schemes)
  else (
    (* Recursive: bind every name to a fresh MONOMORPHIC variable, elaborate all
       right-hand sides against those, then generalize. Keeping the recursive
       names monomorphic during elaboration is what forbids polymorphic
       recursion (undecidable in HM). *)
    enter_level ();
    let recvars = List.map (fun (b : Ast.binding) -> b.name, new_var !current_level) bs in
    let env_rec =
      List.fold_left (fun g (n, tv) -> Env.add n (dont_generalize tv) g) env recvars
    in
    List.iter
      (fun (b : Ast.binding) ->
         let rhs = lambdas b.params b.body in
         let t = infer denv env_rec rhs in
         unify ~span:b.bspan t (List.assoc b.name recvars))
      bs;
    leave_level ();
    List.fold_left (fun g (n, tv) -> Env.add n (generalize tv) g) env recvars)
;;

(* ------------------------------------------------------------------ *)
(* Top-level entry points *)

(* Infer the principal scheme of a single (closed) expression. *)
let infer_scheme (denv : denv) (env : Env.t) (e : Ast.expr) : scheme =
  current_level := 0;
  enter_level ();
  let t = infer denv env e in
  leave_level ();
  generalize t
;;

(* Elaborate a whole program: register type declarations, then thread the
   environment through the [let] declarations in order. Returns the declaration
   environment and the inferred scheme of each top-level binding. *)
let infer_program (prog : Ast.program) : denv * (string * scheme) list =
  reset ();
  let denv = new_denv () in
  let env = ref Env.empty in
  let results = ref [] in
  List.iter
    (fun item ->
       match item with
       | Ast.IType td -> register_type denv td
       | Ast.ILet (is_rec, bs, _) ->
         let env' = infer_bindings denv !env is_rec bs in
         List.iter
           (fun (b : Ast.binding) ->
              match Env.find b.name env' with
              | Some s -> results := (b.name, s) :: !results
              | None -> ())
           bs;
         env := env'
       | Ast.IExpr e ->
         current_level := 0;
         enter_level ();
         let t = infer denv !env e in
         leave_level ();
         results := ("_", generalize t) :: !results)
    prog;
  denv, List.rev !results
;;
