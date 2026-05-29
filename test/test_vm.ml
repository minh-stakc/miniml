(** Bytecode-VM tests (v0.5).

    - {b differential}: for each closed expression, the VM result must equal the
      reference evaluator's result ([Value.equal]) — the two back-ends are checked
      against each other;
    - a few pinned result strings;
    - {b proper tail calls}: a tail-recursive loop of 100000 iterations runs in
      constant frame-stack depth. *)

open Test_util
module Value = Miniml.Value

let vm_run (s : string) : Value.t = Miniml.Vm.run_expr (parse_expr s)
let ev_run (s : string) : Value.t = Miniml.Eval.run (parse_expr s)

(* shared expression corpus, exercising closures, recursion, ADTs, nesting *)
let corpus =
  [ "arith", "1 + 2 * 3 - 4"
  ; "apply", "(fun x -> x + 1) 10"
  ; "curry", "(fun x -> fun y -> x + y) 3 4"
  ; "if", "if 2 < 3 then 1 else 0"
  ; "bool", "true && (false || true)"
  ; "factorial", "let rec fact = fun n -> if n = 0 then 1 else n * fact (n - 1) in fact 6"
  ; ( "map"
    , "let rec map = fun f -> fun xs -> match xs with [] -> [] | h :: t -> f h :: map f \
       t in map (fun x -> x * 2) [1; 2; 3]" )
  ; ( "fold"
    , "let rec fold = fun f -> fun acc -> fun xs -> match xs with [] -> acc | h :: t -> \
       fold f (f acc h) t in fold (fun a -> fun b -> a + b) 0 [1; 2; 3; 4; 5]" )
  ; ( "length"
    , "let rec length = fun xs -> match xs with [] -> 0 | _ :: t -> 1 + length t in \
       length [9; 8; 7]" )
  ; "match_some", "match Some 5 with None -> 0 | Some x -> x"
  ; ( "safe_div_ok"
    , "let d = fun a -> fun b -> if b = 0 then None else Some (a / b) in d 10 2" )
  ; ( "safe_div_none"
    , "let d = fun a -> fun b -> if b = 0 then None else Some (a / b) in d 7 0" )
  ; "tuple_list", "(1, true, [1; 2; 3])"
  ; ( "mutual"
    , "let rec even = fun n -> if n = 0 then true else odd (n - 1) and odd = fun n -> if \
       n = 0 then false else even (n - 1) in even 11" )
  ; "nested_match", "match (Some 1, Some 2) with (Some a, Some b) -> a + b | _ -> 0"
  ; "cons_pattern", "let x = [1; 2; 3] in match x with a :: b :: _ -> a + b | _ -> 0"
  ; ( "compose"
    , "let compose = fun f -> fun g -> fun x -> f (g x) in compose (fun x -> x + 1) (fun \
       x -> x * 2) 10" )
  ; "data_nested", "Node (Leaf, 5, Node (Leaf, 3, Leaf))"
  ; "closure_capture", "let add = fun x -> fun y -> x + y in let inc = add 1 in inc 41"
  ; "poly_id_pair", "let id = fun x -> x in (id 1, id true)"
  ]
;;

let differential =
  List.map
    (fun (name, src) ->
       Alcotest.test_case name `Quick (fun () ->
         Alcotest.(check bool)
           ("VM result equals evaluator result for: " ^ src)
           true
           (Value.equal (ev_run src) (vm_run src))))
    corpus
;;

let pinned =
  [ ( "factorial_120"
    , "let rec f = fun n -> if n = 0 then 1 else n * f (n - 1) in f 5"
    , "120" )
  ; ( "map_doubles"
    , "let rec map = fun f -> fun xs -> match xs with [] -> [] | h :: t -> f h :: map f \
       t in map (fun x -> x * 2) [1; 2; 3]"
    , "[2; 4; 6]" )
  ; ( "none"
    , "let d = fun a -> fun b -> if b = 0 then None else Some (a / b) in d 7 0"
    , "None" )
  ; "tuple", "(1, 2, 3)", "(1, 2, 3)"
  ]
;;

let pinned_cases =
  List.map
    (fun (name, src, expected) ->
       Alcotest.test_case name `Quick (fun () ->
         Alcotest.(check string) src expected (Value.to_string (vm_run src))))
    pinned
;;

let tail_calls =
  Alcotest.test_case "tail_recursion_constant_space" `Quick (fun () ->
    let src =
      "let rec loop = fun n -> fun acc -> if n = 0 then acc else loop (n - 1) (acc + n) \
       in loop 100000 0"
    in
    let v = vm_run src in
    Alcotest.(check string) "sum 1..100000" "5000050000" (Value.to_string v);
    Alcotest.(check bool)
      (Printf.sprintf "frame depth stayed constant (max = %d)" !Miniml.Vm.max_frame_depth)
      true
      (!Miniml.Vm.max_frame_depth <= 5))
;;

let suites =
  [ "vm-differential", differential
  ; "vm-pinned", pinned_cases
  ; "vm-tailcalls", [ tail_calls ]
  ]
;;
