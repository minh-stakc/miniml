(** Decision-tree pattern-match compilation (Maranget, "Compiling Pattern
    Matching to Good Decision Trees", ML 2008).

    The naive strategy in {!Compile} tests each clause independently, so clauses
    that share an outer constructor re-examine it. This builds a {b decision tree}
    from the whole clause matrix: each sub-value (an {e occurrence} — a path from
    the scrutinee, [int list]) is tested at most once on any path, and clauses
    branch only on what differs.

    The tree is built purely over patterns — no runtime values — and lowered to
    bytecode by {!Compile.tree_match}. Without the type environment we cannot tell
    whether a {e user} constructor signature is complete, so such [Switch] nodes
    always carry a [Fail] default (sound, only mildly suboptimal on exhaustive
    matches); built-in [bool]/[list] completeness is recognized and the default is
    omitted. See [docs/09-decision-trees.md]. *)

open Ast

type tree =
  | Leaf of int * (string * int list) list
    (* a clause body to run (by clause index) and the variables it binds,
       each named with the occurrence holding its value *)
  | Fail (* no clause matches: a runtime match failure *)
  | Switch of int list * (Bytecode.test * tree) list * tree option
(* test the value at this occurrence; branch by constructor; optional default *)

(* The head constructor of a pattern ([None] for a wildcard or variable). *)
type head =
  | HInt of int
  | HBool of bool
  | HUnit
  | HNil
  | HCons
  | HTuple of int
  | HUser of string

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

(* Sub-patterns exposed by matching a pattern's head constructor. Enumerated
   rather than defaulted, so a new pattern form must be handled here too. *)
let subpatterns (p : pat) : pat list =
  match p with
  | PCons (h, t, _) -> [ h; t ]
  | PTuple (ps, _) -> ps
  | PCtor (_, Some a, _) -> [ a ]
  | PCtor (_, None, _) | PWild _ | PVar _ | PLit _ | PNil _ -> []
;;

let test_of_head (h : head) : Bytecode.test =
  match h with
  | HInt n -> Bytecode.TInt n
  | HBool b -> Bytecode.TBool b
  | HNil -> Bytecode.TNil
  | HCons -> Bytecode.TCons
  | HUser c -> Bytecode.TTag c
  | HUnit | HTuple _ -> assert false (* irrefutable: compiled without a test *)
;;

(* A row of the clause matrix: the remaining columns (each a pattern paired with
   the occurrence it scrutinizes), the clause index, and the variables bound so
   far on this path. *)
type row =
  { cols : (pat * int list) list
  ; action : int
  ; binds : (string * int list) list
  }

let build (clauses : (pat * int) list) : tree =
  let rec go (rows : row list) : tree =
    match rows with
    | [] -> Fail
    | r0 :: _ when List.for_all (fun (p, _) -> head_of_pat p = None) r0.cols ->
      (* the first row is all wildcards/variables: it matches unconditionally *)
      let vbinds =
        List.filter_map
          (fun (p, occ) ->
             match p with
             | PVar (x, _) -> Some (x, occ)
             | _ -> None)
          r0.cols
      in
      Leaf (r0.action, r0.binds @ vbinds)
    | r0 :: _ ->
      (* pick the leftmost column in which the first row has a constructor *)
      let j =
        let rec find i = function
          | (p, _) :: rest -> if head_of_pat p <> None then i else find (i + 1) rest
          | [] -> assert false (* first row is not all-wildcard, so one exists *)
        in
        find 0 r0.cols
      in
      let occ_j = snd (List.nth r0.cols j) in
      let col_pat row = fst (List.nth row.cols j) in
      let drop_col row = List.filteri (fun i _ -> i <> j) row.cols in
      let heads =
        List.fold_left
          (fun acc row ->
             match head_of_pat (col_pat row) with
             | Some h when not (List.mem h acc) -> acc @ [ h ]
             | _ -> acc)
          []
          rows
      in
      (* arity of head [h], read from a representative pattern in column j *)
      let arity_of h =
        let rec rep = function
          | row :: rest ->
            let p = col_pat row in
            if head_of_pat p = Some h then List.length (subpatterns p) else rep rest
          | [] -> 0
        in
        rep rows
      in
      let specialize h a =
        List.filter_map
          (fun row ->
             let p = col_pat row in
             let rest = drop_col row in
             match head_of_pat p with
             | Some h' when h' = h ->
               let subcols = List.mapi (fun k sp -> sp, occ_j @ [ k ]) (subpatterns p) in
               Some { row with cols = subcols @ rest }
             | None ->
               (* wildcard/variable matches [h]; expose [a] fresh wildcards *)
               let subcols = List.init a (fun k -> PWild Span.dummy, occ_j @ [ k ]) in
               let binds =
                 match p with
                 | PVar (x, _) -> (x, occ_j) :: row.binds
                 | _ -> row.binds
               in
               Some { cols = subcols @ rest; action = row.action; binds }
             | Some _ -> None (* a different constructor: this row cannot match *))
          rows
      in
      let default () =
        List.filter_map
          (fun row ->
             match head_of_pat (col_pat row) with
             | Some _ -> None
             | None ->
               let binds =
                 match col_pat row with
                 | PVar (x, _) -> (x, occ_j) :: row.binds
                 | _ -> row.binds
               in
               Some { cols = drop_col row; action = row.action; binds })
          rows
      in
      (match heads with
       (* single irrefutable constructor: no test, just expose the fields *)
       | [ HUnit ] -> go (specialize HUnit 0)
       | [ HTuple n ] -> go (specialize (HTuple n) n)
       | _ ->
         let branches =
           List.map (fun h -> test_of_head h, go (specialize h (arity_of h))) heads
         in
         let complete =
           (List.mem (HBool true) heads && List.mem (HBool false) heads)
           || (List.mem HNil heads && List.mem HCons heads)
         in
         let default_tree = if complete then None else Some (go (default ())) in
         Switch (occ_j, branches, default_tree))
  in
  go (List.map (fun (p, action) -> { cols = [ p, [] ]; action; binds = [] }) clauses)
;;
