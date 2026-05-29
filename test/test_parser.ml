(** Lexer + parser + pretty-printer tests (v0.1).

    - golden: pretty-printing a parsed expression yields an exact string, pinning
      down operator precedence and associativity;
    - idempotence: [pp (pp s) = pp s] — parsing then printing is stable;
    - parses-ok: larger programs (comments, ADTs, recursion) parse cleanly. *)

open Test_util

let pp (s : string) : string = Miniml.Pretty.expr (parse_expr s)
let pp_prog (s : string) : string = Miniml.Pretty.program (parse_prog s)

let golden =
  [ "add_mul", "1 + 2 * 3", "1 + 2 * 3"
  ; "paren_mul", "(1 + 2) * 3", "(1 + 2) * 3"
  ; "sub_left", "1 - 2 - 3", "1 - 2 - 3"
  ; "cons_right", "a :: b :: c", "a :: b :: c"
  ; "app_left", "f a b", "f a b"
  ; "app_nested_arg", "f (g x)", "f (g x)"
  ; "cmp_vs_add", "a + b < c", "a + b < c"
  ; "and_or", "a || b && c", "a || b && c"
  ; "neg", "-x + 1", "-x + 1"
  ; "ctor_app", "Some (1 + 2)", "Some (1 + 2)"
  ; "list_sugar", "[1; 2; 3]", "1 :: 2 :: 3 :: []"
  ; "if_then_else", "if a then b else c", "if a then b else c"
  ]
;;

let golden_cases =
  List.map
    (fun (name, input, expected) ->
       Alcotest.test_case name `Quick (fun () ->
         Alcotest.(check string) input expected (pp input)))
    golden
;;

let idem_inputs =
  [ "let f x y = x + y in f 1 2"
  ; "fun x -> fun y -> x"
  ; "match xs with [] -> 0 | h :: t -> h"
  ; "let rec map f xs = match xs with [] -> [] | x :: t -> f x :: map f t in map"
  ; "(1, true, x)"
  ; "a = b && c <> d"
  ; "not (a || b)"
  ; "Cons (1, Cons (2, Nil))"
  ; "match o with Some x -> x | None -> 0"
  ; "if a then if b then c else d else e"
  ]
;;

let idem_cases =
  List.map
    (fun input ->
       Alcotest.test_case input `Quick (fun () ->
         let once = pp input in
         Alcotest.(check string) "stable" once (pp once)))
    idem_inputs
;;

let prog_idem_inputs =
  [ "type 'a option = None | Some of 'a"
  ; "type 'a tree = Leaf | Node of 'a tree * 'a * 'a tree"
  ; "let x = 1 let y = 2 let z = x + y"
  ; "type color = Red | Green | Blue let c = Red"
  ]
;;

let prog_idem_cases =
  List.map
    (fun input ->
       Alcotest.test_case input `Quick (fun () ->
         let once = pp_prog input in
         Alcotest.(check string) "stable" once (pp_prog once)))
    prog_idem_inputs
;;

let ok_inputs =
  [ "comment", "(* a comment *) 1 + 2"
  ; "nested_comment", "1 (* outer (* inner *) still *) + 2"
  ; ( "map_fold"
    , "let rec map = fun f -> fun xs -> match xs with [] -> [] | x :: tl -> f x :: map f \
       tl in let rec fold = fun f -> fun acc -> fun xs -> match xs with [] -> acc | x :: \
       tl -> fold f (f acc x) tl in fold" )
  ]
;;

let ok_cases =
  List.map
    (fun (name, input) ->
       Alcotest.test_case name `Quick (fun () -> ignore (parse_expr input)))
    ok_inputs
;;

let suites =
  [ "pretty-golden", golden_cases
  ; "idempotence", idem_cases
  ; "prog-idempotence", prog_idem_cases
  ; "parses-ok", ok_cases
  ]
;;
