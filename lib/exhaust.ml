(** Pattern-match exhaustiveness and redundancy checking — Maranget's usefulness
    algorithm ("Warnings for pattern matching", JFP 2007).

    The core is [useful P q]: is the pattern vector [q] {e useful} with respect to
    the matrix [P]? — i.e. is there a value matched by [q] but by no row of [P]?
    Two corollaries drive the checks:
    - a match with pattern column [P] is {b exhaustive} iff the wildcard vector
      [_] is {e not} useful w.r.t. [P]; if it is useful, the algorithm returns a
      {b witness}: an unmatched pattern;
    - row [i] is {b redundant} (unreachable) iff its pattern is not useful w.r.t.
      the rows above it.

    The constructive version is implemented directly (it returns the witness, not
    just a boolean), so witness generation stays in lock-step with the usefulness
    decision — the two must split on the same complete/incomplete signature test
    or the "witness" can be a value that is actually covered.

    The scrutinee's type is recovered from the constructors that appear in the
    patterns (and the ADT environment), so no separate type information is needed:
    a column with no constructors is necessarily covered by a wildcard. See
    [docs/04-exhaustiveness.md]. *)

open Ast
open Types

(* A head constructor: the top shape of a pattern, with literals treated as
   nullary constructors. Wildcards/variables have no head. *)
type head =
  | HInt of int
  | HBool of bool
  | HUnit
  | HNil
  | HCons
  | HTuple of int
  | HUser of string

let dummy = Span.dummy

(* The matrix is a list of rows; every row is a pattern vector of equal width. *)
type matrix = pat list list

let head_of_pat (p : pat) : head option =
  match p with
  | PWild _ | PVar _ -> None
  | PLit (LInt n, _) -> Some (HInt n)
  | PLit (LBool b, _) -> Some (HBool b)
  | PLit (LUnit, _) -> Some HUnit
  | PNil _ -> Some HNil
  | PCons _ -> Some HCons
  | PTuple (ps, _) -> Some (HTuple (List.length ps))
  | PCtor (c, _, _) -> Some (HUser c)
;;

(* The sub-patterns exposed when we match on a pattern's head constructor. *)
let subpatterns_of_pat (p : pat) : pat list =
  match p with
  | PCons (h, t, _) -> [ h; t ]
  | PTuple (ps, _) -> ps
  | PCtor (_, Some a, _) -> [ a ]
  | _ -> []
;;

let arity_of_pat (p : pat) : int = List.length (subpatterns_of_pat p)

(* Arity of a head constructor (used to expand wildcards and rebuild witnesses).
   Only [HUser] needs the environment. *)
let arity_of_head (denv : denv) (h : head) : int =
  match h with
  | HInt _ | HBool _ | HUnit | HNil -> 0
  | HCons -> 2
  | HTuple n -> n
  | HUser c ->
    (match Hashtbl.find_opt denv.ctors c with
     | Some { ci_arg = Some _; _ } -> 1
     | _ -> 0)
;;

(* Rebuild a pattern from a head and the right number of sub-patterns. *)
let rebuild (h : head) (args : pat list) : pat =
  match h, args with
  | HInt n, _ -> PLit (LInt n, dummy)
  | HBool b, _ -> PLit (LBool b, dummy)
  | HUnit, _ -> PLit (LUnit, dummy)
  | HNil, _ -> PNil dummy
  | HCons, [ a; b ] -> PCons (a, b, dummy)
  | HTuple _, _ -> PTuple (args, dummy)
  | HUser c, [] -> PCtor (c, None, dummy)
  | HUser c, [ a ] -> PCtor (c, Some a, dummy)
  | _ -> assert false (* arity mismatch: caller bug *)
;;

(* The full constructor set of the column's type, inferred from any head present.
   [None] means "infinite or undeterminable" (an [int] column, or a column of
   only wildcards): such a signature is never complete. *)
let full_ctor_set (denv : denv) (sigma : head list) : (head * int) list option =
  match sigma with
  | [] -> None
  | h :: _ ->
    (match h with
     | HInt _ -> None
     | HBool _ -> Some [ HBool true, 0; HBool false, 0 ]
     | HUnit -> Some [ HUnit, 0 ]
     | HNil | HCons -> Some [ HNil, 0; HCons, 2 ]
     | HTuple n -> Some [ HTuple n, n ]
     | HUser c ->
       (match Hashtbl.find_opt denv.ctors c with
        | None -> None
        | Some ci ->
          (match Hashtbl.find_opt denv.types ci.ci_type with
           | None -> None
           | Some ti ->
             Some
               (List.map
                  (fun cname -> HUser cname, arity_of_head denv (HUser cname))
                  ti.ti_ctors))))
;;

let complete (denv : denv) (sigma : head list) : bool =
  match full_ctor_set denv sigma with
  | None -> false
  | Some all -> List.for_all (fun (h, _) -> List.mem h sigma) all
;;

(* When the signature is incomplete, pick a representative unmatched pattern:
   a missing constructor (with wildcard arguments) for a finite type, otherwise a
   plain wildcard (e.g. "some other int", or an all-wildcard column). *)
let witness_head (denv : denv) (sigma : head list) : pat =
  match full_ctor_set denv sigma with
  | None -> PWild dummy
  | Some all ->
    (match List.find_opt (fun (h, _) -> not (List.mem h sigma)) all with
     | None -> PWild dummy
     | Some (h, arity) -> rebuild h (List.init arity (fun _ -> PWild dummy)))
;;

(* Specialize the matrix by head [h] of arity [a]: keep rows whose first pattern
   matches [h] (exposing its sub-patterns) or is a wildcard (expanded to [a]
   wildcards); drop rows headed by a different constructor. *)
let specialize (h : head) (a : int) (m : matrix) : matrix =
  List.filter_map
    (fun row ->
       match row with
       | [] -> None
       | p :: ps ->
         (match head_of_pat p with
          | None -> Some (List.init a (fun _ -> PWild dummy) @ ps)
          | Some h' -> if h' = h then Some (subpatterns_of_pat p @ ps) else None))
    m
;;

(* Default matrix: keep only rows whose first pattern is a wildcard, dropping its
   (covered) head column. *)
let default (m : matrix) : matrix =
  List.filter_map
    (fun row ->
       match row with
       | [] -> None
       | p :: ps ->
         (match head_of_pat p with
          | None -> Some ps
          | Some _ -> None))
    m
;;

(* Distinct head constructors appearing in the first column. *)
let column_heads (m : matrix) : head list =
  let seen = ref [] in
  List.iter
    (fun row ->
       match row with
       | p :: _ ->
         (match head_of_pat p with
          | Some h when not (List.mem h !seen) -> seen := h :: !seen
          | _ -> ())
       | [] -> ())
    m;
  List.rev !seen
;;

let rec first_some : pat list option list -> pat list option = function
  | [] -> None
  | (Some _ as s) :: _ -> s
  | None :: rest -> first_some rest
;;

let split_at (n : int) (xs : 'a list) : 'a list * 'a list =
  let rec go n acc xs =
    if n = 0
    then List.rev acc, xs
    else (
      match xs with
      | [] -> List.rev acc, []
      | y :: ys -> go (n - 1) (y :: acc) ys)
  in
  go n [] xs
;;

(* [useful denv m q] returns [Some witness] if [q] is useful w.r.t. [m] (i.e.
   there is a value matched by [q] but no row of [m]); the witness is such a
   value, expressed as a pattern vector. Returns [None] if [q] is useless. *)
let rec useful (denv : denv) (m : matrix) (q : pat list) : pat list option =
  match q with
  | [] -> if m = [] then Some [] else None
  | q1 :: qs ->
    (match head_of_pat q1 with
     | Some h ->
       let a = arity_of_pat q1 in
       (match useful denv (specialize h a m) (subpatterns_of_pat q1 @ qs) with
        | None -> None
        | Some w ->
          let args, rest = split_at a w in
          Some (rebuild h args :: rest))
     | None ->
       let sigma = column_heads m in
       if complete denv sigma
       then
         (* the column is a complete signature: q (a wildcard here) is useful iff
            it is useful under some constructor *)
         first_some
           (List.map
              (fun h ->
                 let a = arity_of_head denv h in
                 match
                   useful denv (specialize h a m) (List.init a (fun _ -> PWild dummy) @ qs)
                 with
                 | None -> None
                 | Some w ->
                   let args, rest = split_at a w in
                   Some (rebuild h args :: rest))
              sigma)
       else (
         (* incomplete: recurse on the default matrix and prepend an unmatched head *)
         match useful denv (default m) qs with
         | None -> None
         | Some w -> Some (witness_head denv sigma :: w)))
;;

(* ------------------------------------------------------------------ *)
(* Public interface *)

type result =
  { exhaustive : bool
  ; witness : pat option (* a counterexample, when not exhaustive *)
  ; redundant : int list (* indices (0-based) of unreachable rows *)
  }

let check (denv : denv) (cases : case list) : result =
  let rows = List.map (fun (c : case) -> [ c.lhs ]) cases in
  let exhaustive, witness =
    match useful denv rows [ PWild dummy ] with
    | None -> true, None
    | Some [ w ] -> false, Some w
    | Some _ -> false, None
  in
  let redundant = ref [] in
  List.iteri
    (fun i (c : case) ->
       let above = List.filteri (fun j _ -> j < i) rows in
       match useful denv above [ c.lhs ] with
       | None -> redundant := i :: !redundant
       | Some _ -> ())
    cases;
  { exhaustive; witness; redundant = List.rev !redundant }
;;
