(** Type-inference tests (v0.2).

    Two groups matter most:
    - {b principal types}: canonical terms infer their most general type;
    - {b adversarial}: deliberate stress tests of generalization, levels, the
      occurs check, and the monomorphism of lambda- and let-rec-bound variables.
      A type-directed (well-typed-by-construction) property generator can never
      reach these — they exercise the {e rejection} path and the level
      distinction — so they are hand-written. See [docs/03-type-inference.md]. *)

open Test_util

(* Run inference and reduce the result to a comparable string tag. *)
let classify ?(denv = Miniml.Types.new_denv ()) (s : string) : string =
  match Miniml.Infer.infer_scheme denv Miniml.Env.empty (parse_expr s) with
  | sch -> "ok: " ^ Miniml.Pretty.scheme sch
  | exception Miniml.Infer.Occurs_check _ -> "occurs"
  | exception Miniml.Infer.Type_error _ -> "type_error"
;;

let denv_of_decls (decls : string list) : Miniml.Types.denv =
  let denv = Miniml.Types.new_denv () in
  List.iter
    (fun d ->
       match parse_prog d with
       | [ Miniml.Ast.IType td ] -> Miniml.Types.register_type denv td
       | _ -> failwith "test: expected a single type declaration")
    decls;
  denv
;;

let case ?denv name input expected =
  Alcotest.test_case name `Quick (fun () ->
    Alcotest.(check string) input expected (classify ?denv input))
;;

(* -- principal types ------------------------------------------------ *)

let principal =
  [ case "id" "fun x -> x" "ok: 'a -> 'a"
  ; case "const" "fun x -> fun y -> x" "ok: 'a -> 'b -> 'a"
  ; case "twice" "fun f -> fun x -> f (f x)" "ok: ('a -> 'a) -> 'a -> 'a"
  ; case
      "compose"
      "fun f -> fun g -> fun x -> f (g x)"
      "ok: ('a -> 'b) -> ('c -> 'a) -> 'c -> 'b"
  ; case "succ" "fun x -> x + 1" "ok: int -> int"
  ; case "pair" "(1, true)" "ok: int * bool"
  ; case "nil" "[]" "ok: 'a list"
  ; case
      "map"
      "let rec map = fun f -> fun xs -> match xs with [] -> [] | h :: t -> f h :: map f \
       t in map"
      "ok: ('a -> 'b) -> 'a list -> 'b list"
  ; case
      "length"
      "let rec length = fun xs -> match xs with [] -> 0 | _ :: t -> 1 + length t in \
       length"
      "ok: 'a list -> int"
  ]
;;

(* -- adversarial: generalization, levels, occurs, monomorphism ------ *)

let adversarial =
  [ case "poly_id_use" "let id = fun x -> x in (id 1, id true)" "ok: int * bool"
  ; case "mono_lambda" "fun f -> (f 1, f true)" "type_error"
  ; case "occurs" "fun x -> x x" "occurs"
  ; case "let_mono_level" "fun x -> let y = x in (y, y)" "ok: 'a -> 'a * 'a"
  ; case
      "const_poly"
      "let const = fun x -> fun y -> x in (const 1 true, const true 1)"
      "ok: int * bool"
  ; case "no_poly_rec" "let rec f = fun x -> (f 1, f true) in f" "type_error"
  ; case
      "mutual_rec"
      "let rec even = fun n -> if n = 0 then true else odd (n - 1) and odd = fun n -> if \
       n = 0 then false else even (n - 1) in even 10"
      "ok: bool"
  ; case "list_elem_clash" "1 :: [true]" "type_error"
  ; case
      "empty_list_poly"
      "let xs = [] in (1 :: xs, true :: xs)"
      "ok: int list * bool list"
  ; case
      "value_higher_order"
      "let pair = fun x -> (x, x) in pair (fun z -> z)"
      "ok: ('a -> 'a) * ('a -> 'a)"
  ; case "unbound" "y" "type_error"
  ; (* found by the adversarial review: linearity, let-rec, value restriction *)
    case "nonlinear_pattern" "match (1, true) with (x, x) -> x" "type_error"
  ; case "letrec_non_function" "let rec x = x + 1 in x" "type_error"
  ; case
      "value_restriction"
      "let b = (fun f -> f) (fun y -> y) in let g = b in (g 1, g true)"
      "type_error"
  ; case
      "value_restriction_ok_for_values"
      "let b = fun y -> y in (b 1, b true)"
      "ok: int * bool"
  ; case "negative_int_pattern" "match 0 - 1 with -1 -> 100 | _ -> 0" "ok: int"
  ]
;;

(* -- algebraic data types ------------------------------------------- *)

let opt = denv_of_decls [ "type 'a option = None | Some of 'a" ]
let tree = denv_of_decls [ "type 'a tree = Leaf | Node of 'a tree * 'a * 'a tree" ]

let adt =
  [ case ~denv:opt "some" "Some 3" "ok: int option"
  ; case ~denv:opt "none" "None" "ok: 'a option"
  ; case
      ~denv:opt
      "match_opt"
      "fun o -> match o with Some x -> x | None -> 0"
      "ok: int option -> int"
  ; case ~denv:tree "leaf" "Leaf" "ok: 'a tree"
  ; case
      ~denv:tree
      "tree_match"
      "fun t -> match t with Leaf -> 0 | Node (l, v, r) -> v"
      "ok: int tree -> int"
  ]
;;

let suites =
  [ "infer-principal", principal; "infer-adversarial", adversarial; "infer-adt", adt ]
;;
