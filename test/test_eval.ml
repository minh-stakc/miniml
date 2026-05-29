(** Reference evaluator tests (v0.4).

    Evaluate closed expressions and check the printed result. These also serve as
    the oracle the VM is differentially tested against in v0.5. *)

open Test_util

let run_str (s : string) : string =
  Miniml.Value.to_string (Miniml.Eval.run (parse_expr s))
;;

let eval_cases =
  [ "arith_prec", "1 + 2 * 3", "7"
  ; "paren", "(1 + 2) * 3", "9"
  ; "sub_left", "10 - 3 - 2", "5"
  ; "apply", "(fun x -> x + 1) 10", "11"
  ; "closure", "(fun x -> fun y -> x + y) 3 4", "7"
  ; "if", "if 2 < 3 then 1 else 0", "1"
  ; "bool", "true && false || true", "true"
  ; "neg", "let x = 5 in -x + 2", "-3"
  ; ( "factorial"
    , "let rec fact = fun n -> if n = 0 then 1 else n * fact (n - 1) in fact 5"
    , "120" )
  ; "list_lit", "[1; 2; 3]", "[1; 2; 3]"
  ; ( "map"
    , "let rec map = fun f -> fun xs -> match xs with [] -> [] | h :: t -> f h :: map f \
       t in map (fun x -> x * 2) [1; 2; 3]"
    , "[2; 4; 6]" )
  ; ( "fold"
    , "let rec fold = fun f -> fun acc -> fun xs -> match xs with [] -> acc | h :: t -> \
       fold f (f acc h) t in fold (fun a -> fun b -> a + b) 0 [1; 2; 3; 4]"
    , "10" )
  ; ( "length"
    , "let rec length = fun xs -> match xs with [] -> 0 | _ :: t -> 1 + length t in \
       length [1; 2; 3; 4; 5]"
    , "5" )
  ; "tuple", "(1, true, 3)", "(1, true, 3)"
  ; "ctor_data", "Some (1 + 2)", "Some 3"
  ; "match_some", "match Some 5 with None -> 0 | Some x -> x", "5"
  ; ( "safe_div"
    , "let safe_div = fun a -> fun b -> if b = 0 then None else Some (a / b) in safe_div \
       10 2"
    , "Some 5" )
  ; ( "mutual_even"
    , "let rec even = fun n -> if n = 0 then true else odd (n - 1) and odd = fun n -> if \
       n = 0 then false else even (n - 1) in even 10"
    , "true" )
  ; "poly_id", "let id = fun x -> x in id 42", "42"
  ; "structural_eq", "(1, 2) = (1, 2)", "true"
  ]
;;

let eval_cases_alco =
  List.map
    (fun (name, input, expected) ->
       Alcotest.test_case name `Quick (fun () ->
         Alcotest.(check string) input expected (run_str input)))
    eval_cases
;;

(* A whole-program test: evaluate top-level declarations, inspect a binding. *)
let program_case =
  Alcotest.test_case "tree_size_program" `Quick (fun () ->
    let prog =
      parse_prog
        "type 'a tree = Leaf | Node of 'a tree * 'a * 'a tree\n\
         let rec size = fun t -> match t with Leaf -> 0 | Node (l, v, r) -> size l + 1 + \
         size r\n\
         let answer = size (Node (Node (Leaf, 1, Leaf), 2, Node (Leaf, 3, Leaf)))"
    in
    let env = Miniml.Eval.eval_program prog in
    Alcotest.(check string)
      "answer"
      "3"
      (Miniml.Value.to_string (List.assoc "answer" env)))
;;

let suites = [ "eval", eval_cases_alco; "eval-program", [ program_case ] ]
