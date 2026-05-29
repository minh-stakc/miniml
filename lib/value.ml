(** Runtime values, shared by the reference evaluator ([Eval]) and the bytecode
    VM ([Vm], v0.5). Sharing one representation is what lets differential testing
    compare the two back-ends with a single structural [equal].

    Constructors carry their {e name} (not an integer tag), which keeps values
    readable when printed; the VM's pattern-match compilation dispatches on the
    name. Lists have their own [VList] case so they print as [\[1; 2; 3\]]. A
    MiniML constructor takes at most one argument (a tuple if it is "n-ary", e.g.
    [Node (l, v, r)]), so [VData] carries an optional single value. *)

type t =
  | VInt of int
  | VBool of bool
  | VUnit
  | VTuple of t list
  | VList of t list
  | VData of string * t option (* constructor name + optional argument *)
  | VClosEval of eval_closure (* a closure produced by the tree-walking evaluator *)

and eval_closure =
  { param : string
  ; cbody : Ast.expr (* [cbody] not [body], to avoid clashing with [Ast.binding.body] *)
  ; mutable eenv : (string * t) list (* mutable for let-rec knot-tying *)
  }

(** Structural equality. Closures are opaque (never equal): differential tests
    compare first-order results, never functions. *)
let rec equal (a : t) (b : t) : bool =
  match a, b with
  | VInt x, VInt y -> x = y
  | VBool x, VBool y -> x = y
  | VUnit, VUnit -> true
  | VTuple xs, VTuple ys | VList xs, VList ys ->
    List.length xs = List.length ys && List.for_all2 equal xs ys
  | VData (c1, a1), VData (c2, a2) ->
    c1 = c2
    &&
      (match a1, a2 with
      | None, None -> true
      | Some x, Some y -> equal x y
      | _ -> false)
  | _ -> false
;;

let rec to_string (v : t) : string =
  match v with
  | VInt n -> string_of_int n
  | VBool b -> string_of_bool b
  | VUnit -> "()"
  | VTuple vs -> "(" ^ String.concat ", " (List.map to_string vs) ^ ")"
  | VList vs -> "[" ^ String.concat "; " (List.map to_string vs) ^ "]"
  | VData (c, None) -> c
  | VData (c, Some v) -> c ^ " " ^ to_string_atom v
  | VClosEval _ -> "<fun>"

and to_string_atom (v : t) : string =
  match v with
  | VInt n when n < 0 -> "(" ^ string_of_int n ^ ")"
  | VData (_, Some _) -> "(" ^ to_string v ^ ")"
  | _ -> to_string v
;;
