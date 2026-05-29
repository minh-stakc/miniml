(** Driver / REPL integration tests (v0.7): feed phrases and check the rendered
    output (inferred types, values via the VM, and diagnostics). *)

module D = Miniml.Driver

let run_session (inputs : string list) : string list =
  let st = ref (D.initial ()) in
  List.map
    (fun s ->
       let st', out = D.feed !st s in
       st := st';
       out)
    inputs
;;

let contains (sub : string) (s : string) : bool =
  let n = String.length sub
  and m = String.length s in
  let rec go i = i + n <= m && (String.equal (String.sub s i n) sub || go (i + 1)) in
  n = 0 || go 0
;;

let suites =
  [ ( "driver"
    , [ Alcotest.test_case "types_and_values" `Quick (fun () ->
          let o =
            run_session
              [ "let id = fun x -> x"
              ; "id 42"
              ; "let rec fact = fun n -> if n = 0 then 1 else n * fact (n - 1)"
              ; "fact 6"
              ; "(id 1, id true)"
              ]
          in
          Alcotest.(check string) "id type" "id : 'a -> 'a = <fun>" (List.nth o 0);
          Alcotest.(check string) "id 42" "- : int = 42" (List.nth o 1);
          Alcotest.(check string) "fact 6" "- : int = 720" (List.nth o 3);
          Alcotest.(check string) "poly use" "- : int * bool = (1, true)" (List.nth o 4))
      ; Alcotest.test_case "type_error_reported" `Quick (fun () ->
          let o = run_session [ "1 + true" ] in
          Alcotest.(check bool) "mentions bool" true (contains "bool" (List.nth o 0)))
      ; Alcotest.test_case "occurs_reported" `Quick (fun () ->
          let o = run_session [ "fun x -> x x" ] in
          Alcotest.(check bool)
            "infinite type"
            true
            (contains "infinite type" (List.nth o 0)))
      ; Alcotest.test_case "nonexhaustive_warning" `Quick (fun () ->
          let o =
            run_session
              [ "type 'a option = None | Some of 'a"; "match Some 5 with Some x -> x" ]
          in
          Alcotest.(check bool) "warns" true (contains "not exhaustive" (List.nth o 1)))
      ] )
  ; (* robustness: runtime/lex errors must be reported, never crash the REPL
       (found by the adversarial review) *)
    ( "driver-robustness"
    , [ Alcotest.test_case "div_by_zero_graceful" `Quick (fun () ->
          Alcotest.(check bool)
            "reports"
            true
            (contains "division by zero" (List.hd (run_session [ "10 / 0" ]))))
      ; Alcotest.test_case "runtime_match_failure_graceful" `Quick (fun () ->
          Alcotest.(check bool)
            "reports"
            true
            (contains
               "match failure"
               (List.hd (run_session [ "(fun xs -> match xs with h :: _ -> h) []" ]))))
      ; Alcotest.test_case "big_int_graceful" `Quick (fun () ->
          Alcotest.(check bool)
            "reports"
            true
            (contains
               "out of range"
               (List.hd (run_session [ "99999999999999999999999999" ]))))
      ; Alcotest.test_case "let_underscore" `Quick (fun () ->
          Alcotest.(check string)
            "_"
            "_ : int = 3"
            (List.hd (run_session [ "let _ = 1 + 2" ])))
      ] )
  ]
;;
