(** Reference tree-walking evaluator.

    A small, obviously-correct big-step interpreter over the surface AST. Its job
    is to be the {e oracle} for differential testing: the bytecode VM (v0.5) must
    agree with it on every program. Because correctness-by-inspection matters more
    than speed here, it uses an association-list environment and structural
    pattern matching. It assumes its input type-checked (it raises
    [Runtime_error] on stuck states a well-typed program can never reach). *)

open Ast
open Value

exception Runtime_error of string

let rec lambdas (params : string list) (body : expr) : expr =
  match params with
  | [] -> body
  | p :: ps -> EFun (p, lambdas ps body, span_of_expr body)
;;

type env = (string * Value.t) list

let rec eval (env : env) (e : expr) : Value.t =
  match e with
  | ELit (LInt n, _) -> VInt n
  | ELit (LBool b, _) -> VBool b
  | ELit (LUnit, _) -> VUnit
  | EVar (x, _) ->
    (match List.assoc_opt x env with
     | Some v -> v
     | None -> raise (Runtime_error ("unbound variable " ^ x)))
  | EFun (x, body, _) -> VClosEval { param = x; cbody = body; eenv = env }
  | EApp (f, a, _) ->
    let vf = eval env f in
    let va = eval env a in
    (match vf with
     | VClosEval c -> eval ((c.param, va) :: c.eenv) c.cbody
     | _ -> raise (Runtime_error "applied a non-function"))
  | EIf (c, t, e, _) ->
    (match eval env c with
     | VBool true -> eval env t
     | VBool false -> eval env e
     | _ -> raise (Runtime_error "if condition is not a boolean"))
  | ELet (is_rec, bs, body, _) ->
    let env' = eval_bindings env is_rec bs in
    eval env' body
  | ETuple (es, _) -> VTuple (List.map (eval env) es)
  | ENil _ -> VList []
  | ECons (h, t, _) ->
    let vh = eval env h in
    (match eval env t with
     | VList l -> VList (vh :: l)
     | _ -> raise (Runtime_error "tail of :: is not a list"))
  | ECtor (c, None, _) -> VData (c, None)
  | ECtor (c, Some e, _) -> VData (c, Some (eval env e))
  | EMatch (scrut, cases, _) -> eval_match env (eval env scrut) cases
  | EBinop (op, a, b, _) ->
    (* left-to-right, to match the VM (which pushes [a] then [b]) *)
    let va = eval env a in
    let vb = eval env b in
    eval_binop op va vb
  | EUnop (Neg, a, _) ->
    (match eval env a with
     | VInt n -> VInt (-n)
     | _ -> raise (Runtime_error "negation of a non-integer"))
  | EUnop (Not, a, _) ->
    (match eval env a with
     | VBool b -> VBool (not b)
     | _ -> raise (Runtime_error "not of a non-boolean"))
  | ESeq (a, b, _) ->
    ignore (eval env a);
    eval env b

and eval_binop (op : binop) (a : Value.t) (b : Value.t) : Value.t =
  let int2 f =
    match a, b with
    | VInt x, VInt y -> f x y
    | _ -> raise (Runtime_error "arithmetic on non-integers")
  in
  match op with
  | Add -> int2 (fun x y -> VInt (x + y))
  | Sub -> int2 (fun x y -> VInt (x - y))
  | Mul -> int2 (fun x y -> VInt (x * y))
  | Div ->
    int2 (fun x y ->
      if y = 0 then raise (Runtime_error "division by zero") else VInt (x / y))
  | Lt -> int2 (fun x y -> VBool (x < y))
  | Le -> int2 (fun x y -> VBool (x <= y))
  | Gt -> int2 (fun x y -> VBool (x > y))
  | Ge -> int2 (fun x y -> VBool (x >= y))
  | Eq -> VBool (Value.equal a b)
  | Neq -> VBool (not (Value.equal a b))
  | And ->
    (match a, b with
     | VBool x, VBool y -> VBool (x && y)
     | _ -> raise (Runtime_error "&& on non-booleans"))
  | Or ->
    (match a, b with
     | VBool x, VBool y -> VBool (x || y)
     | _ -> raise (Runtime_error "|| on non-booleans"))

and eval_match (env : env) (v : Value.t) (cases : case list) : Value.t =
  match cases with
  | [] -> raise (Runtime_error "match failure (no case matched)")
  | { lhs; rhs } :: rest ->
    (match match_pat lhs v with
     | Some binds -> eval (binds @ env) rhs
     | None -> eval_match env v rest)

and match_pat (p : pat) (v : Value.t) : (string * Value.t) list option =
  let ( let* ) o f = Option.bind o f in
  match p, v with
  | PWild _, _ -> Some []
  | PVar (x, _), _ -> Some [ x, v ]
  | PLit (LInt n, _), VInt m -> if n = m then Some [] else None
  | PLit (LBool b, _), VBool c -> if b = c then Some [] else None
  | PLit (LUnit, _), VUnit -> Some []
  | PNil _, VList [] -> Some []
  | PCons (hp, tp, _), VList (h :: t) ->
    let* b1 = match_pat hp h in
    let* b2 = match_pat tp (VList t) in
    Some (b1 @ b2)
  | PTuple (ps, _), VTuple vs when List.length ps = List.length vs ->
    List.fold_left2
      (fun acc p v ->
         let* a = acc in
         let* b = match_pat p v in
         Some (a @ b))
      (Some [])
      ps
      vs
  | PCtor (c, None, _), VData (c', None) -> if c = c' then Some [] else None
  | PCtor (c, Some p, _), VData (c', Some v) -> if c = c' then match_pat p v else None
  | _ -> None

and eval_bindings (env : env) (is_rec : bool) (bs : binding list) : env =
  if not is_rec
  then
    (* non-recursive (incl. parallel [and]): each rhs sees the outer env only *)
    List.fold_left
      (fun acc (b : binding) -> (b.name, eval env (lambdas b.params b.body)) :: acc)
      env
      bs
  else (
    (* recursive: build closures over a shared, knot-tied environment *)
    let placeholders =
      List.map
        (fun (b : binding) ->
           match lambdas b.params b.body with
           | EFun (p, body, _) -> b.name, { param = p; cbody = body; eenv = [] }
           | _ -> raise (Runtime_error "recursive binding is not a function"))
        bs
    in
    let env' =
      List.fold_left
        (fun acc (name, clos) -> (name, VClosEval clos) :: acc)
        env
        placeholders
    in
    List.iter (fun (_, clos) -> clos.eenv <- env') placeholders;
    env')
;;

(* ------------------------------------------------------------------ *)
(* Entry points *)

let run (e : expr) : Value.t = eval [] e

(* Evaluate a whole program (type declarations are no-ops at runtime) and return
   the final top-level environment of bound names. *)
let eval_program (prog : program) : env =
  List.fold_left
    (fun env item ->
       match item with
       | IType _ -> env
       | ILet (is_rec, bs, _) -> eval_bindings env is_rec bs
       | IExpr e ->
         ignore (eval env e);
         env)
    []
    prog
;;
