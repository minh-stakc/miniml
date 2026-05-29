(** Exhaustiveness / redundancy tests (v0.3).

    Each case parses a [match] expression, runs [Exhaust.check], and asserts the
    exhaustiveness verdict, the witness (counterexample) pattern, and the set of
    redundant rows. A final group checks that inference actually surfaces the
    warnings. *)

open Test_util
module E = Miniml.Exhaust

let cases_of (s : string) : Miniml.Ast.case list =
  match parse_expr s with
  | Miniml.Ast.EMatch (_, cases, _) -> cases
  | _ -> failwith "test: expected a match expression"
;;

let witness_str (r : E.result) : string =
  match r.E.witness with
  | Some p -> Miniml.Pretty.pat p
  | None -> "<none>"
;;

let opt = Test_infer.denv_of_decls [ "type 'a option = None | Some of 'a" ]
let color = Test_infer.denv_of_decls [ "type color = Red | Green | Blue" ]

let check_case ?(denv = Miniml.Types.new_denv ()) name src ~exhaustive ~witness ~redundant
  =
  Alcotest.test_case name `Quick (fun () ->
    let r = E.check denv (cases_of src) in
    Alcotest.(check bool) "exhaustive" exhaustive r.E.exhaustive;
    Alcotest.(check string) "witness" witness (witness_str r);
    Alcotest.(check (list int)) "redundant" redundant r.E.redundant)
;;

let suite_builtin =
  [ check_case
      "bool_full"
      "match x with true -> 1 | false -> 2"
      ~exhaustive:true
      ~witness:"<none>"
      ~redundant:[]
  ; check_case
      "bool_partial"
      "match x with true -> 1"
      ~exhaustive:false
      ~witness:"false"
      ~redundant:[]
  ; check_case
      "list_full"
      "match x with [] -> 0 | h :: t -> 1"
      ~exhaustive:true
      ~witness:"<none>"
      ~redundant:[]
  ; check_case
      "list_no_cons"
      "match x with [] -> 0"
      ~exhaustive:false
      ~witness:"_ :: _"
      ~redundant:[]
  ; check_case
      "list_no_nil"
      "match x with h :: t -> 1"
      ~exhaustive:false
      ~witness:"[]"
      ~redundant:[]
  ; check_case
      "wildcard"
      "match x with _ -> 0"
      ~exhaustive:true
      ~witness:"<none>"
      ~redundant:[]
  ; check_case
      "int_partial"
      "match n with 0 -> 1 | 1 -> 2"
      ~exhaustive:false
      ~witness:"_"
      ~redundant:[]
  ; check_case
      "int_wild"
      "match n with 0 -> 1 | _ -> 2"
      ~exhaustive:true
      ~witness:"<none>"
      ~redundant:[]
  ; check_case
      "redundant_after_wild"
      "match x with _ -> 0 | true -> 1"
      ~exhaustive:true
      ~witness:"<none>"
      ~redundant:[ 1 ]
  ; check_case
      "tuple_partial"
      "match p with (true, x) -> 1"
      ~exhaustive:false
      ~witness:"(false, _)"
      ~redundant:[]
  ; check_case
      "tuple_full"
      "match p with (true, _) -> 1 | (false, true) -> 2 | (false, false) -> 3"
      ~exhaustive:true
      ~witness:"<none>"
      ~redundant:[]
  ]
;;

let suite_adt =
  [ check_case
      ~denv:opt
      "opt_full"
      "match o with None -> 0 | Some x -> x"
      ~exhaustive:true
      ~witness:"<none>"
      ~redundant:[]
  ; check_case
      ~denv:opt
      "opt_no_none"
      "match o with Some x -> x"
      ~exhaustive:false
      ~witness:"None"
      ~redundant:[]
  ; check_case
      ~denv:opt
      "opt_no_some"
      "match o with None -> 0"
      ~exhaustive:false
      ~witness:"Some _"
      ~redundant:[]
  ; check_case
      ~denv:opt
      "opt_nested"
      "match o with Some (Some x) -> x | Some None -> 0 | None -> 1"
      ~exhaustive:true
      ~witness:"<none>"
      ~redundant:[]
  ; check_case
      ~denv:color
      "color_partial"
      "match c with Red -> 1 | Green -> 2"
      ~exhaustive:false
      ~witness:"Blue"
      ~redundant:[]
  ; check_case
      ~denv:color
      "color_full"
      "match c with Red -> 1 | Green -> 2 | Blue -> 3"
      ~exhaustive:true
      ~witness:"<none>"
      ~redundant:[]
  ]
;;

(* Inference surfaces the warnings. *)
let warns ?(denv = Miniml.Types.new_denv ()) name src n =
  Alcotest.test_case name `Quick (fun () ->
    Miniml.Infer.reset ();
    ignore (Miniml.Infer.infer_scheme denv Miniml.Env.empty (parse_expr src));
    Alcotest.(check int) "warning count" n (List.length (Miniml.Infer.get_warnings ())))
;;

let suite_integration =
  [ warns ~denv:opt "warn_partial" "fun o -> match o with Some x -> x" 1
  ; warns "warn_exhaustive" "fun b -> match b with true -> 1 | false -> 2" 0
  ; warns "warn_redundant" "fun x -> match x with _ -> 0 | true -> 1" 1
  ]
;;

let suites =
  [ "exhaust-builtin", suite_builtin
  ; "exhaust-adt", suite_adt
  ; "exhaust-integration", suite_integration
  ]
;;
