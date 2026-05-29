(** The type representation — the heart of the inferencer.

    A monotype {!typ} is a tree whose leaves are {e mutable} type variables. Each
    variable is a union-find node ([tvar ref]):
    - [Unbound (id, level)] is a representative (a root): an as-yet-unknown type,
      tagged with the [level] at which it was created;
    - [Link t] points at the type the variable was unified with (a union-find
      parent pointer).

    {2 Levels}

    Plain Algorithm W decides which variables to generalize at a [let] by
    computing [ftv(τ) \ ftv(Γ)] — the free variables of the inferred type that do
    {e not} also occur in the environment. Scanning the whole environment is
    expensive. Instead we follow Rémy's trick: a global "current level" counter is
    incremented on entry to each [let] right-hand side. Every fresh variable
    records the level at which it was born. A variable may be generalized at a
    [let] iff its level is {e strictly greater} than the level outside that [let]
    — i.e. it was created inside the right-hand side and has not escaped into the
    surrounding context. Unification keeps levels honest by lowering them (see
    [Infer.occurs_adjust]). This is the single most error-prone part of the whole
    project; see [docs/03-type-inference.md]. *)

type level = int

type tvar =
  | Unbound of int * level
  | Link of typ

and typ =
  | TVar of tvar ref
  | TArrow of typ * typ
  | TTuple of typ list
  | TCon of string * typ list (* [int] = TCon("int",[]); ['a list] = TCon("list",[a]) *)

(** A type scheme [∀ qvars. body]: [qvars] are the ids of the generalized
    (universally quantified) variables appearing in [body]. A monotype is the
    degenerate scheme with [qvars = []]. *)
type scheme =
  { qvars : int list
  ; body : typ
  }

(* ------------------------------------------------------------------ *)
(* Fresh variables *)

let counter = ref 0
let reset_counter () = counter := 0

let fresh_id () =
  incr counter;
  !counter
;;

let new_var (lvl : level) : typ = TVar (ref (Unbound (fresh_id (), lvl)))

(** Union-find {e find} with path compression: follow [Link] chains to the
    representative, short-circuiting the pointers traversed. *)
let rec repr (t : typ) : typ =
  match t with
  | TVar ({ contents = Link t' } as r) ->
    let t'' = repr t' in
    r := Link t'';
    t''
  | _ -> t
;;

(* ------------------------------------------------------------------ *)
(* Base types *)

let t_int = TCon ("int", [])
let t_bool = TCon ("bool", [])
let t_unit = TCon ("unit", [])
let t_list (elt : typ) : typ = TCon ("list", [ elt ])
let t_ref (t : typ) : typ = TCon ("ref", [ t ])

(* ------------------------------------------------------------------ *)
(* Declaration environment: user-defined algebraic data types.

   Shared by the inferencer (to type constructor uses and patterns) and the
   exhaustiveness checker (to know each type's full constructor set). *)

type ctor_info =
  { ci_name : string
  ; ci_type : string (* the ADT this constructor belongs to, e.g. "option" *)
  ; ci_arg : Ast.ty_expr option (* declared argument type, in terms of ci_tparams *)
  ; ci_tparams : string list (* the ADT's type parameters, e.g. ["a"] *)
  }

type type_info =
  { ti_name : string
  ; ti_params : string list
  ; ti_ctors : string list (* all constructor names, in declaration order *)
  }

type denv =
  { ctors : (string, ctor_info) Hashtbl.t
  ; types : (string, type_info) Hashtbl.t
  }

let new_denv () : denv = { ctors = Hashtbl.create 32; types = Hashtbl.create 16 }

(** Register a [type] declaration's constructors and constructor set. *)
let register_type (denv : denv) (td : Ast.tdecl) : unit =
  let ctor_names = List.map fst td.tctors in
  Hashtbl.replace
    denv.types
    td.tname
    { ti_name = td.tname; ti_params = td.tparams; ti_ctors = ctor_names };
  List.iter
    (fun (cname, arg) ->
       Hashtbl.replace
         denv.ctors
         cname
         { ci_name = cname; ci_type = td.tname; ci_arg = arg; ci_tparams = td.tparams })
    td.tctors
;;
