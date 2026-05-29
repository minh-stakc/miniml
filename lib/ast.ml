(** Surface syntax — the tree produced by the parser, before type inference.

    Every node carries a {!Span.t} for diagnostics. Surface sugar is desugared
    into this core by the parser:
    - [fun x y -> e] and [let f x y = e] become nested single-argument lambdas
      (lambdas are curried);
    - the list literal [\[a; b; c\]] becomes [ECons (a, ECons (b, ECons (c, ENil)))].

    Lists are kept as dedicated nodes ([ENil]/[ECons], [PNil]/[PCons]) rather
    than as ordinary constructors; the type checker, exhaustiveness checker, and
    compiler treat [list] as a built-in two-constructor type ([\[\]], [::]). *)

type lit =
  | LInt of int
  | LBool of bool
  | LUnit

type binop =
  | Add
  | Sub
  | Mul
  | Div
  | Lt
  | Le
  | Gt
  | Ge
  | Eq
  | Neq
  | And
  | Or

type unop =
  | Neg
  | Not

type pat =
  | PWild of Span.t
  | PVar of string * Span.t
  | PLit of lit * Span.t
  | PTuple of pat list * Span.t
  | PCtor of string * pat option * Span.t (* [None] / [Some p] *)
  | PNil of Span.t (* [\[\]] *)
  | PCons of pat * pat * Span.t (* [h :: t] *)

type expr =
  | EVar of string * Span.t
  | ELit of lit * Span.t
  | EFun of string * expr * Span.t (* single (curried) parameter *)
  | EApp of expr * expr * Span.t
  | ELet of bool * binding list * expr * Span.t (* is_rec; list for [and] *)
  | EIf of expr * expr * expr * Span.t
  | ETuple of expr list * Span.t
  | ENil of Span.t
  | ECons of expr * expr * Span.t
  | ECtor of string * expr option * Span.t
  | EMatch of expr * case list * Span.t
  | EBinop of binop * expr * expr * Span.t
  | EUnop of unop * expr * Span.t
  | ESeq of expr * expr * Span.t (* [e1; e2] — sequencing (useful with refs) *)

and binding =
  { name : string
  ; params :
      string list (* [\[\]] for a plain [let x = e]; non-empty for [let f x y = e] *)
  ; body : expr
  ; bspan : Span.t
  }

and case =
  { lhs : pat
  ; rhs : expr
  }

(** A user type expression, as written in a [type] declaration's constructor
    arguments (e.g. the ['a tree * 'a * 'a tree] in [Node of 'a tree * 'a * 'a tree]). *)
type ty_expr =
  | TyVar of string
  | TyCon of string * ty_expr list (* [int], [bool], ['a list], ['a tree] *)
  | TyArrow of ty_expr * ty_expr
  | TyTuple of ty_expr list

type tdecl =
  { tname : string (* e.g. ["option"] *)
  ; tparams : string list (* e.g. [\["a"\]] for ['a option] *)
  ; tctors : (string * ty_expr option) list (* [("Some", Some (TyVar "a"))] *)
  ; tdspan : Span.t
  }

type item =
  | IType of tdecl
  | ILet of bool * binding list * Span.t
  | IExpr of expr

type program = item list

(* ------------------------------------------------------------------ *)
(* Span accessors *)

let span_of_pat : pat -> Span.t = function
  | PWild s
  | PVar (_, s)
  | PLit (_, s)
  | PTuple (_, s)
  | PCtor (_, _, s)
  | PNil s
  | PCons (_, _, s) -> s
;;

let span_of_expr : expr -> Span.t = function
  | EVar (_, s)
  | ELit (_, s)
  | EFun (_, _, s)
  | EApp (_, _, s)
  | ELet (_, _, _, s)
  | EIf (_, _, _, s)
  | ETuple (_, s)
  | ENil s
  | ECons (_, _, s)
  | ECtor (_, _, s)
  | EMatch (_, _, s)
  | EBinop (_, _, _, s)
  | EUnop (_, _, s)
  | ESeq (_, _, s) -> s
;;

let string_of_binop : binop -> string = function
  | Add -> "+"
  | Sub -> "-"
  | Mul -> "*"
  | Div -> "/"
  | Lt -> "<"
  | Le -> "<="
  | Gt -> ">"
  | Ge -> ">="
  | Eq -> "="
  | Neq -> "<>"
  | And -> "&&"
  | Or -> "||"
;;

let string_of_unop : unop -> string = function
  | Neg -> "-"
  | Not -> "not"
;;
