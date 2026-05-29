(** The surface syntax produced by the parser, before type inference.

    Every node carries a {!Span.t} for diagnostics. Surface sugar is desugared
    into this core by the parser: [fun x y -> e] becomes nested single-argument
    lambdas, and [\[a; b; c\]] becomes [ECons (a, ECons (b, ECons (c, ENil)))].
    Lists are kept as dedicated nodes (treated as a built-in two-constructor
    type), as are mutable references and records. *)

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
  | PCtor of string * pat option * Span.t (** [None] / [Some p] *)
  | PNil of Span.t
  | PCons of pat * pat * Span.t

type expr =
  | EVar of string * Span.t
  | ELit of lit * Span.t
  | EFun of string * expr * Span.t (** single (curried) parameter *)
  | EApp of expr * expr * Span.t
  | ELet of bool * binding list * expr * Span.t (** is_rec; list for [and] *)
  | EIf of expr * expr * expr * Span.t
  | ETuple of expr list * Span.t
  | ENil of Span.t
  | ECons of expr * expr * Span.t
  | ECtor of string * expr option * Span.t
  | EMatch of expr * case list * Span.t
  | EBinop of binop * expr * expr * Span.t
  | EUnop of unop * expr * Span.t
  | ESeq of expr * expr * Span.t (** [e1; e2] *)
  | ERef of expr * Span.t (** [ref e] *)
  | EDeref of expr * Span.t (** [!e] *)
  | EAssign of expr * expr * Span.t (** [e1 := e2] *)
  | ERecord of (string * expr) list * Span.t (** [{ x = e1; y = e2 }] *)
  | EField of expr * string * Span.t (** [e.x] *)

and binding =
  { name : string
  ; params : string list (** empty for [let x = e]; non-empty for [let f x y = e] *)
  ; body : expr
  ; bspan : Span.t
  }

and case =
  { lhs : pat
  ; rhs : expr
  }

(** A type expression, as written in a [type] declaration's constructor
    arguments (e.g. ['a tree * 'a * 'a tree]). *)
type ty_expr =
  | TyVar of string
  | TyCon of string * ty_expr list
  | TyArrow of ty_expr * ty_expr
  | TyTuple of ty_expr list

type tdecl =
  { tname : string (** e.g. ["option"] *)
  ; tparams : string list (** e.g. [\["a"\]] for ['a option] *)
  ; tctors : (string * ty_expr option) list
  ; tdspan : Span.t
  }

type item =
  | IType of tdecl
  | ILet of bool * binding list * Span.t
  | IExpr of expr

type program = item list

val span_of_pat : pat -> Span.t
val span_of_expr : expr -> Span.t
val string_of_binop : binop -> string
val string_of_unop : unop -> string
