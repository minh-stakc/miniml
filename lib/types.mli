(** The type representation — the heart of the inferencer.

    A monotype {!typ} is a tree whose leaves are {e mutable} type variables, each
    a union-find node: [Unbound (id, level)] is a representative tagged with the
    {e level} at which it was created (used for generalization), and [Link t] is a
    parent pointer. Row variables (for records) are ordinary [TVar]s appearing in
    row position. See [docs/03-type-inference.md]. *)

type level = int

type tvar =
  | Unbound of int * level
  | Link of typ

and typ =
  | TVar of tvar ref
  | TArrow of typ * typ
  | TTuple of typ list
  | TCon of string * typ list
  (** [int] = [TCon ("int", [])]; ['a list] = [TCon ("list", [a])] *)
  | TRecord of typ (** a record over a row, e.g. [{ x : int; .. }] *)
  | TRowEmpty (** the closed/empty row tail *)
  | TRowExtend of string * typ * typ (** [label : field_type] then the rest of the row *)

(** A type scheme [∀ qvars. body]: [qvars] are the ids of the generalized
    variables in [body]. A monotype is the degenerate scheme with [qvars = []]. *)
type scheme =
  { qvars : int list
  ; body : typ
  }

(** Reset the fresh-variable counter (for deterministic ids per program). *)
val reset_counter : unit -> unit

(** [new_var level] is a fresh unbound type variable born at [level]. *)
val new_var : level -> typ

(** Union-find {e find} with path compression: the representative of [t]. *)
val repr : typ -> typ

val t_int : typ
val t_bool : typ
val t_unit : typ
val t_list : typ -> typ
val t_ref : typ -> typ

(** Information about one data constructor of a user [type] declaration. *)
type ctor_info =
  { ci_name : string
  ; ci_type : string (** the ADT this constructor belongs to *)
  ; ci_arg : Ast.ty_expr option (** declared argument type, in terms of [ci_tparams] *)
  ; ci_tparams : string list
  }

type type_info =
  { ti_name : string
  ; ti_params : string list
  ; ti_ctors : string list (** all constructor names, in declaration order *)
  }

(** The declaration environment of user ADTs, shared by the inferencer and the
    exhaustiveness checker. *)
type denv =
  { ctors : (string, ctor_info) Hashtbl.t
  ; types : (string, type_info) Hashtbl.t
  }

val new_denv : unit -> denv

(** Register a [type] declaration's constructors and constructor set. *)
val register_type : denv -> Ast.tdecl -> unit
