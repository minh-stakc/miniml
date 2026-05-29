(** Pattern-match compilation: the two strategies must agree (v1.1).

    MiniML has two match compilers — the naive per-clause sequence and the
    optimizing Maranget decision tree ({!Miniml.Decision_tree}). This suite is the
    guardrail that makes the optimization safe: on a hand corpus that stresses
    shared prefixes/depths, and on a property over generated well-typed programs,
    the {b evaluator}, the {b naive VM}, and the {b decision-tree VM} must all
    produce the same value. *)

open Test_util
module Value = Miniml.Value
module Compile = Miniml.Compile

(* Compile + run [e] under a given match strategy, then restore the default. *)
let run_with (s : Compile.strategy) (e : Miniml.Ast.expr) : Value.t =
  Compile.strategy := s;
  let v = Miniml.Vm.run_expr e in
  Compile.strategy := Compile.Decision_tree;
  v
;;

(* Evaluator result == naive-VM result == decision-tree-VM result. *)
let three_agree (e : Miniml.Ast.expr) : bool =
  let ev = Miniml.Eval.run e in
  let naive = run_with Compile.Naive e in
  let dtree = run_with Compile.Decision_tree e in
  Value.equal ev naive && Value.equal ev dtree
;;

let corpus =
  [ ( "shared_tuple_fst"
    , "match (1, true) with (1, true) -> 10 | (1, false) -> 20 | (_, _) -> 30" )
  ; ( "bool_grid"
    , "match (true, false) with (true, true) -> 1 | (true, false) -> 2 | (false, true) \
       -> 3 | (false, false) -> 4" )
  ; "list_depths", "match [1; 2; 3] with [] -> 0 | x :: [] -> x | x :: y :: _ -> x + y"
  ; ( "nested_option"
    , "match Some (Some 5) with Some (Some x) -> x | Some None -> 0 | None -> 1" )
  ; "mixed_wild", "match (3, 4) with (0, _) -> 0 | (_, 0) -> 1 | (a, b) -> a + b"
  ; ( "cons_depths"
    , "match [1; 2] with x :: y :: z :: _ -> 0 | x :: y :: _ -> x + y | _ -> 99" )
  ; "shared_bind", "match (5, 6) with (x, 0) -> x | (x, y) -> x * y"
  ; "int_literals", "match 2 with 0 -> 0 | 1 -> 1 | 2 -> 22 | _ -> 99"
  ; "first_match_wins", "match (0, 0) with (0, _) -> 1 | (_, 0) -> 2 | _ -> 3"
  ]
;;

let corpus_cases =
  List.map
    (fun (name, src) ->
       Alcotest.test_case name `Quick (fun () ->
         Alcotest.(check bool)
           "evaluator = naive VM = decision-tree VM"
           true
           (three_agree (parse_expr src))))
    corpus
;;

(* The number of comparison sites (TEST instructions) [e] compiles to under a
   given strategy — the cost metric the bench reports. *)
let count_tests (s : Compile.strategy) (e : Miniml.Ast.expr) : int =
  Compile.strategy := s;
  let code = Miniml.Compile.compile_expr e in
  Compile.strategy := Compile.Decision_tree;
  Array.fold_left
    (fun n i ->
       match i with
       | Miniml.Bytecode.TEST _ -> n + 1
       | _ -> n)
    0
    code
;;

(* Guardrail for the "optimizing" claim: the decision tree must never emit more
   comparison sites than the naive strategy on any case... *)
let cost_cases =
  List.map
    (fun (name, src) ->
       Alcotest.test_case name `Quick (fun () ->
         let e = parse_expr src in
         let naive = count_tests Compile.Naive e in
         let tree = count_tests Compile.Decision_tree e in
         Alcotest.(check bool)
           (Printf.sprintf "decision tree (%d) <= naive (%d) comparison sites" tree naive)
           true
           (tree <= naive)))
    corpus
;;

(* ...and strictly fewer in total, so the optimization is real, not a no-op. *)
let cost_total =
  Alcotest.test_case "strictly fewer comparison sites overall" `Quick (fun () ->
    let total s =
      List.fold_left (fun acc (_, src) -> acc + count_tests s (parse_expr src)) 0 corpus
    in
    let naive = total Compile.Naive
    and tree = total Compile.Decision_tree in
    Alcotest.(check bool)
      (Printf.sprintf "decision-tree total %d < naive total %d" tree naive)
      true
      (tree < naive))
;;

(* Over generated well-typed programs (which include list matches), all three
   back-ends must agree. *)
let prop_agree =
  QCheck.Test.make
    ~count:500
    ~name:"naive and decision-tree match compilers agree with the evaluator"
    Test_soundness.arb
    three_agree
;;

let suites =
  [ "match-strategies-corpus", corpus_cases
  ; "match-strategies-cost", cost_cases @ [ cost_total ]
  ; "match-strategies-property", [ QCheck_alcotest.to_alcotest prop_agree ]
  ]
;;
