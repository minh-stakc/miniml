(* Measures what the optimizing match compiler buys.

   Each [match] is compiled twice — with the naive per-clause strategy and with
   the Maranget decision tree — and we count the comparison sites each emits: the
   number of [TEST] instructions in the bytecode, plus total code length. The
   decision tree tests each occurrence at most once per path, so on matches that
   share outer structure it emits strictly fewer comparisons; on already-flat
   matches the two coincide. The figures here are pasted into REPORT.md and are
   reproducible with [dune exec bench/bench.exe]. *)

open Miniml

let parse (s : string) : Ast.expr = Parser.expr_main Lexer.token (Lexing.from_string s)

(* (number of TEST instructions, total instructions) emitted for [e] under [strat]. *)
let measure (strat : Compile.strategy) (e : Ast.expr) : int * int =
  Compile.strategy := strat;
  let code = Compile.compile_expr e in
  Compile.strategy := Compile.Decision_tree;
  let tests =
    Array.fold_left
      (fun n i ->
         match i with
         | Bytecode.TEST _ -> n + 1
         | _ -> n)
      0
      code
  in
  tests, Array.length code
;;

(* The same corpus the differential tests use: matches that stress shared
   prefixes, nested constructors, and varying depth. *)
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

let () =
  Printf.printf "| match | naive TESTs | tree TESTs | naive instrs | tree instrs |\n";
  Printf.printf "| --- | ---: | ---: | ---: | ---: |\n";
  let sum_nt = ref 0
  and sum_dt = ref 0
  and sum_ni = ref 0
  and sum_di = ref 0 in
  List.iter
    (fun (name, src) ->
       let e = parse src in
       let nt, ni = measure Compile.Naive e in
       let dt, di = measure Compile.Decision_tree e in
       sum_nt := !sum_nt + nt;
       sum_dt := !sum_dt + dt;
       sum_ni := !sum_ni + ni;
       sum_di := !sum_di + di;
       Printf.printf "| `%s` | %d | %d | %d | %d |\n" name nt dt ni di)
    corpus;
  Printf.printf
    "| **total** | **%d** | **%d** | **%d** | **%d** |\n"
    !sum_nt
    !sum_dt
    !sum_ni
    !sum_di;
  let pct = 100. *. float_of_int (!sum_nt - !sum_dt) /. float_of_int !sum_nt in
  Printf.printf
    "\n%d -> %d comparison sites: %.0f%% fewer with the decision tree on this corpus.\n"
    !sum_nt
    !sum_dt
    pct
;;
