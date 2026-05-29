(** Mutable references + value restriction (v1.0).

    - typing: ref/deref/assign types; the {b value restriction} now does real
      work — a polymorphic reference is rejected (the classic unsoundness);
    - behaviour: ref programs (with sequencing) produce the right value, and the
      VM agrees with the reference evaluator. *)

open Test_util
module Value = Miniml.Value

let typ_of (s : string) : string =
  match
    Miniml.Infer.infer_scheme (Miniml.Types.new_denv ()) Miniml.Env.empty (parse_expr s)
  with
  | sch -> "ok: " ^ Miniml.Pretty.scheme sch
  | exception Miniml.Infer.Type_error _ -> "type_error"
  | exception Miniml.Infer.Occurs_check _ -> "occurs"
;;

let vm_value (s : string) : string = Value.to_string (Miniml.Vm.run_expr (parse_expr s))

let agrees (s : string) : bool =
  Value.equal (Miniml.Eval.run (parse_expr s)) (Miniml.Vm.run_expr (parse_expr s))
;;

let tcase name s expected =
  Alcotest.test_case name `Quick (fun () -> Alcotest.(check string) s expected (typ_of s))
;;

let vcase name s expected =
  Alcotest.test_case name `Quick (fun () ->
    Alcotest.(check string) s expected (vm_value s);
    Alcotest.(check bool) "VM = evaluator" true (agrees s))
;;

let typing =
  [ tcase "ref_type" "ref 0" "ok: int ref"
  ; tcase "deref_type" "let r = ref 0 in !r" "ok: int"
  ; tcase "assign_type" "let r = ref 0 in r := 5" "ok: unit"
  ; (* the value restriction in action: a reference cannot be polymorphic *)
    tcase
      "value_restriction_list"
      "let r = ref [] in (r := [1]; r := [true])"
      "type_error"
  ; tcase
      "value_restriction_fun"
      "let r = ref (fun x -> x) in (r := (fun x -> x + 1); !r true)"
      "type_error"
  ; (* sequencing requires the left side to be unit *)
    tcase "seq_requires_unit" "(1 + 1; 2)" "type_error"
  ]
;;

let behaviour =
  [ vcase "get_set" "let r = ref 0 in (r := 10; !r)" "10"
  ; vcase "counter" "let c = ref 0 in (c := !c + 1; c := !c + 1; c := !c + 1; !c)" "3"
  ; vcase "ref_print" "ref 5" "ref 5"
  ; vcase "ref_pair" "let r = ref (1, 2) in !r" "(1, 2)"
  ; vcase
      "ref_through_function"
      "let inc = fun r -> r := !r + 1 in let c = ref 5 in (inc c; inc c; !c)"
      "7"
  ; vcase
      "swap"
      "let a = ref 1 in let b = ref 2 in let t = !a in (a := !b; b := t; (!a, !b))"
      "(2, 1)"
  ]
;;

let suites = [ "refs-typing", typing; "refs-behaviour", behaviour ]
