(** Records with row-polymorphic inference (v1.1).

    - typing: record literals get a closed row; field access is {b row
      polymorphic} ([fun r -> r.x : { x : 'a; .. } -> 'a]), so one function works
      on records of different shapes; absent / mistyped fields are rejected;
    - behaviour: construction, access, nesting — VM agrees with the evaluator. *)

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
  [ tcase "empty" "{}" "ok: {}"
  ; tcase "literal" "{ x = 1; y = true }" "ok: { x : int; y : bool }"
  ; tcase "row_poly_access" "fun r -> r.x" "ok: { x : 'a; .. } -> 'a"
  ; tcase "row_poly_int" "fun r -> r.x + 1" "ok: { x : int; .. } -> int"
  ; tcase "two_field_access" "fun r -> (r.x, r.y)" "ok: { x : 'a; y : 'b; .. } -> 'a * 'b"
  ; tcase "field_concrete" "{ x = 1 }.x" "ok: int"
  ; (* the row-polymorphism payoff: one accessor, two different record shapes *)
    tcase
      "row_poly_two_shapes"
      "let get_x = fun r -> r.x in (get_x { x = 1; y = 2 }, get_x { x = true; z = 5 })"
      "ok: int * bool"
  ; tcase "field_absent" "{ x = 1 }.y" "type_error"
  ; tcase "field_type_clash" "let f = fun r -> r.x + 1 in f { x = true }" "type_error"
  ; tcase "missing_required_field" "let f = fun r -> r.x in f { y = 1 }" "type_error"
  ]
;;

let behaviour =
  [ vcase "construct_access" "{ x = 1; y = 2 }.x" "1"
  ; vcase "sum_fields" "let r = { a = 10; b = 20 } in r.a + r.b" "30"
  ; vcase "row_poly_runtime" "let get = fun r -> r.x in get { x = 42; y = 99 }" "42"
  ; vcase
      "row_poly_two_shapes_runtime"
      "let get_x = fun r -> r.x in (get_x { x = 1; y = 2 }, get_x { x = true; z = 5 })"
      "(1, true)"
  ; vcase "record_print" "{ x = 1; y = true }" "{ x = 1; y = true }"
  ; vcase "nested" "{ p = { x = 1; y = 2 } }.p.x" "1"
  ; vcase "empty" "{}" "{}"
  ; vcase
      "record_via_fun"
      "let mk = fun v -> { value = v } in (mk 1).value + (mk 2).value"
      "3"
  ]
;;

let suites = [ "records-typing", typing; "records-behaviour", behaviour ]
