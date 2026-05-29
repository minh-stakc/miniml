(** Property-tested type soundness (v0.6).

    A {b type-directed generator} produces expressions that are well-typed {e by
    construction}: it generates top-down from a target type, so every leaf and
    every combination respects the types. It deliberately omits recursion and
    division, so every generated program terminates without a (legitimate)
    runtime error.

    The property — a practical "progress + preservation" — is:

    {[ a generated (well-typed) program type-checks, runs on the VM WITHOUT a
       Type_trap, and the VM result equals the reference evaluator's. ]}

    A [Type_trap] (apply a non-function, field of a non-block, if on a non-bool,
    a non-exhaustive [MATCHFAIL]) on type-checked input would be exactly a
    soundness violation; it surfaces here as a failing case with a printed,
    counterexample program.

    NB: this generator cannot exercise the {e rejection} side of the type checker
    (it only builds well-typed terms); over-generalization, the occurs check, and
    the level discipline are covered by the hand-written cases in [test_infer.ml]. *)

module G = QCheck.Gen
module Ast = Miniml.Ast

let sp = Miniml.Span.dummy

(* The (closed) types the generator targets. *)
type gty =
  | GInt
  | GBool
  | GList of gty
  | GPair of gty * gty
  | GArrow of gty * gty

let counter = ref 0

let fresh () =
  incr counter;
  Printf.sprintf "g%d" !counter
;;

let map3 f a b c = G.(a >>= fun x -> b >>= fun y -> map (fun z -> f x y z) c)
let mkbind x rhs : Ast.binding = { name = x; params = []; body = rhs; bspan = sp }

let random_ty : gty G.t =
  G.oneof_list [ GInt; GBool; GList GInt; GArrow (GInt, GInt); GPair (GInt, GBool) ]
;;

let rec gen (ctx : (string * gty) list) (t : gty) (fuel : int) : Ast.expr G.t =
  let var_leaf =
    let vs = List.filter_map (fun (n, ty) -> if ty = t then Some n else None) ctx in
    if vs = [] then [] else [ 2, G.map (fun x -> Ast.EVar (x, sp)) (G.oneof_list vs) ]
  in
  let type_leaf =
    match t with
    | GInt -> [ 3, G.map (fun n -> Ast.ELit (Ast.LInt n, sp)) (G.int_range (-9) 9) ]
    | GBool ->
      [ 3, G.oneof_list [ Ast.ELit (Ast.LBool true, sp); Ast.ELit (Ast.LBool false, sp) ]
      ]
    | GList _ -> [ 3, G.return (Ast.ENil sp) ]
    | GArrow (a, b) ->
      let x = fresh () in
      [ ( 3
        , G.map
            (fun body -> Ast.EFun (x, body, sp))
            (gen ((x, a) :: ctx) b (max 0 (fuel - 1))) )
      ]
    | GPair (a, b) ->
      [ ( 3
        , G.map2
            (fun u v -> Ast.ETuple ([ u; v ], sp))
            (gen ctx a (fuel / 2))
            (gen ctx b (fuel / 2)) )
      ]
  in
  let leaves = type_leaf @ var_leaf in
  if fuel <= 0
  then G.oneof_weighted leaves
  else G.oneof_weighted (leaves @ recursive ctx t fuel)

and recursive ctx t fuel : (int * Ast.expr G.t) list =
  let sub ty = gen ctx ty (fuel - 1) in
  let common =
    [ ( 2
      , map3
          (fun c a b -> Ast.EIf (c, a, b, sp))
          (gen ctx GBool (fuel - 1))
          (sub t)
          (sub t) )
    ; ( 2
      , G.(
          random_ty
          >>= fun s ->
          let x = fresh () in
          map2
            (fun rhs body -> Ast.ELet (false, [ mkbind x rhs ], body, sp))
            (gen ctx s (fuel - 1))
            (gen ((x, s) :: ctx) t (fuel - 1))) )
    ; ( 2
      , G.(
          random_ty
          >>= fun s ->
          map2
            (fun f a -> Ast.EApp (f, a, sp))
            (gen ctx (GArrow (s, t)) (fuel - 1))
            (gen ctx s (fuel - 1))) )
    ]
  in
  let specific =
    match t with
    | GInt ->
      [ 3, G.map2 (fun a b -> Ast.EBinop (Add, a, b, sp)) (sub GInt) (sub GInt)
      ; 2, G.map2 (fun a b -> Ast.EBinop (Sub, a, b, sp)) (sub GInt) (sub GInt)
      ; 2, G.map2 (fun a b -> Ast.EBinop (Mul, a, b, sp)) (sub GInt) (sub GInt)
      ; 2, list_match ctx fuel
      ]
    | GBool ->
      [ 3, G.map2 (fun a b -> Ast.EBinop (Lt, a, b, sp)) (sub GInt) (sub GInt)
      ; 2, G.map2 (fun a b -> Ast.EBinop (Eq, a, b, sp)) (sub GInt) (sub GInt)
      ; 2, G.map2 (fun a b -> Ast.EBinop (And, a, b, sp)) (sub GBool) (sub GBool)
      ; 2, G.map2 (fun a b -> Ast.EBinop (Or, a, b, sp)) (sub GBool) (sub GBool)
      ; 1, G.map (fun a -> Ast.EUnop (Not, a, sp)) (sub GBool)
      ]
    | GList et ->
      [ ( 3
        , G.map2
            (fun h tl -> Ast.ECons (h, tl, sp))
            (gen ctx et (fuel - 1))
            (sub (GList et)) )
      ]
    | GPair _ | GArrow _ -> []
  in
  common @ specific

(* match <int list> with [] -> <int> | h :: t -> <int with h, t in scope> *)
and list_match ctx fuel : Ast.expr G.t =
  let h = fresh () in
  let tl = fresh () in
  map3
    (fun scrut nil_body cons_body ->
       Ast.EMatch
         ( scrut
         , [ { lhs = PNil sp; rhs = nil_body }
           ; { lhs = PCons (PVar (h, sp), PVar (tl, sp), sp); rhs = cons_body }
           ]
         , sp ))
    (gen ctx (GList GInt) (fuel - 1))
    (gen ctx GInt (fuel - 1))
    (gen ((h, GInt) :: (tl, GList GInt) :: ctx) GInt (fuel - 1))
;;

let gen_top : Ast.expr G.t = G.(oneof_list [ GInt; GBool ] >>= fun t -> gen [] t 4)
let arb = QCheck.make ~print:Miniml.Pretty.expr gen_top

let property (e : Ast.expr) : bool =
  let denv = Miniml.Types.new_denv () in
  (* well-typed by construction: a failure here is a generator bug, surfaced as
     an exception (which qcheck reports as a failing case). *)
  ignore (Miniml.Infer.infer_scheme denv Miniml.Env.empty e);
  (* no Type_trap on well-typed input, and the VM agrees with the evaluator.
     (A Type_trap propagates as an exception => failing case.) *)
  Miniml.Value.equal (Miniml.Eval.run e) (Miniml.Vm.run_expr e)
;;

let soundness_test =
  QCheck.Test.make
    ~count:1000
    ~name:"well-typed programs run soundly (VM = evaluator)"
    arb
    property
;;

let suites = [ "soundness", [ QCheck_alcotest.to_alcotest soundness_test ] ]
