(** Pretty-printer for the surface AST.

    Used by the REPL, by round-trip tests (parsing the printed form must yield
    the same AST), and to render pattern witnesses from the exhaustiveness
    checker. Prints with precedence-aware parenthesization.

    Precedence levels (higher binds tighter) mirror the parser's ladder:
    {[
      0  let / fun / if / match / ;     (lowest, extend rightward)
      1  ||
      2  &&
      3  = <> < <= > >=                 (non-associative)
      4  ::                             (right-associative)
      5  + -                            (left-associative)
      6  * /                            (left-associative)
      7  unary - / not
      8  application (incl. constructor application)
      9  atoms
    ]} *)

open Ast

let prec_of_binop = function
  | Or -> 1
  | And -> 2
  | Eq | Neq | Lt | Le | Gt | Ge -> 3
  | Add | Sub -> 5
  | Mul | Div -> 6
;;

(* ------------------------------------------------------------------ *)
(* Patterns *)

let rec pat_str (p : pat) : string =
  match p with
  | PWild _ -> "_"
  | PVar (x, _) -> x
  | PLit (LInt n, _) -> string_of_int n
  | PLit (LBool b, _) -> string_of_bool b
  | PLit (LUnit, _) -> "()"
  | PTuple (ps, _) -> "(" ^ String.concat ", " (List.map pat_str ps) ^ ")"
  | PCtor (c, None, _) -> c
  | PCtor (c, Some p, _) -> c ^ " " ^ pat_atom p
  | PNil _ -> "[]"
  | PCons (h, t, _) -> pat_atom h ^ " :: " ^ pat_str t

and pat_atom (p : pat) : string =
  match p with
  | PWild _ | PVar _ | PLit _ | PTuple _ | PNil _ | PCtor (_, None, _) -> pat_str p
  | _ -> "(" ^ pat_str p ^ ")"
;;

(* ------------------------------------------------------------------ *)
(* Expressions *)

let rec expr_p (ctx : int) (e : expr) : string =
  let p, s = expr_prec e in
  if p < ctx then "(" ^ s ^ ")" else s

and expr_prec (e : expr) : int * string =
  match e with
  | EVar (x, _) -> 9, x
  | ELit (LInt n, _) -> 9, string_of_int n
  | ELit (LBool b, _) -> 9, string_of_bool b
  | ELit (LUnit, _) -> 9, "()"
  | ENil _ -> 9, "[]"
  | ECtor (c, None, _) -> 9, c
  | ETuple (es, _) -> 9, "(" ^ String.concat ", " (List.map (expr_p 0) es) ^ ")"
  | ECtor (c, Some arg, _) -> 8, c ^ " " ^ expr_p 9 arg
  | EApp (f, x, _) -> 8, expr_p 8 f ^ " " ^ expr_p 9 x
  | EUnop (Neg, e, _) -> 7, "-" ^ expr_p 7 e
  | EUnop (Not, e, _) -> 7, "not " ^ expr_p 7 e
  | EBinop (op, a, b, _) ->
    let p = prec_of_binop op in
    let lp, rp =
      match op with
      | Add | Sub | Mul | Div -> p, p + 1 (* left associative *)
      | And | Or -> p + 1, p (* right associative *)
      | _ -> p + 1, p + 1 (* non associative *)
    in
    p, expr_p lp a ^ " " ^ string_of_binop op ^ " " ^ expr_p rp b
  | ECons (h, t, _) -> 4, expr_p 5 h ^ " :: " ^ expr_p 4 t (* right associative *)
  | EIf (c, a, b, _) ->
    0, "if " ^ expr_p 1 c ^ " then " ^ expr_p 1 a ^ " else " ^ expr_p 0 b
  | EFun (x, body, _) -> 0, "fun " ^ x ^ " -> " ^ expr_p 0 body
  | ELet (is_rec, bs, body, _) ->
    let kw = if is_rec then "let rec " else "let " in
    0, kw ^ String.concat " and " (List.map binding_str bs) ^ " in " ^ expr_p 0 body
  | EMatch (scrut, cases, _) ->
    let case (c : case) = "| " ^ pat_str c.lhs ^ " -> " ^ expr_p 0 c.rhs in
    0, "match " ^ expr_p 1 scrut ^ " with " ^ String.concat " " (List.map case cases)
  | ESeq (a, b, _) -> 0, expr_p 1 a ^ "; " ^ expr_p 0 b

and binding_str (b : binding) : string =
  let params = String.concat "" (List.map (fun p -> " " ^ p) b.params) in
  b.name ^ params ^ " = " ^ expr_p 0 b.body
;;

let expr (e : expr) : string = expr_p 0 e
let pat (p : pat) : string = pat_str p

(* Type-expression precedence: arrow (lowest) < tuple < application
   (postfix, e.g. ['a list]) < atom. *)
let rec ty_expr_str (t : ty_expr) : string = ty_arrow t

and ty_arrow (t : ty_expr) : string =
  match t with
  | TyArrow (a, b) -> ty_tuple a ^ " -> " ^ ty_arrow b
  | _ -> ty_tuple t

and ty_tuple (t : ty_expr) : string =
  match t with
  | TyTuple ts -> String.concat " * " (List.map ty_app ts)
  | _ -> ty_app t

and ty_app (t : ty_expr) : string =
  match t with
  | TyCon (name, [ arg ]) -> ty_atom arg ^ " " ^ name
  | TyCon (name, (_ :: _ as args)) ->
    "(" ^ String.concat ", " (List.map ty_expr_str args) ^ ") " ^ name
  | _ -> ty_atom t

and ty_atom (t : ty_expr) : string =
  match t with
  | TyVar a -> "'" ^ a
  | TyCon (name, []) -> name
  | _ -> "(" ^ ty_expr_str t ^ ")"
;;

let item (it : item) : string =
  match it with
  | IExpr e -> expr e
  | ILet (is_rec, bs, _) ->
    let kw = if is_rec then "let rec " else "let " in
    kw ^ String.concat " and " (List.map binding_str bs)
  | IType td ->
    let params =
      match td.tparams with
      | [] -> ""
      | [ a ] -> "'" ^ a ^ " "
      | ps -> "(" ^ String.concat ", " (List.map (fun a -> "'" ^ a) ps) ^ ") "
    in
    let ctor (name, arg) =
      match arg with
      | None -> name
      | Some t -> name ^ " of " ^ ty_expr_str t
    in
    "type " ^ params ^ td.tname ^ " = " ^ String.concat " | " (List.map ctor td.tctors)
;;

let program (p : program) : string = String.concat "\n" (List.map item p)
