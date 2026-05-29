(* MiniML CLI.

   - no arguments: an interactive REPL (lex -> parse -> infer -> exhaustiveness
     -> compile -> VM for every phrase), printing the inferred type and the value;
   - one argument: run that file as a sequence of declarations. *)

let rec repl (st : Miniml.Driver.state) : unit =
  print_string "miniml> ";
  flush stdout;
  match In_channel.input_line stdin with
  | None -> print_newline () (* EOF (Ctrl-D) *)
  | Some line when String.trim line = "" -> repl st
  | Some line ->
    let st', out = Miniml.Driver.feed st line in
    if out <> "" then print_endline out;
    repl st'
;;

let run_file (path : string) : unit =
  let src = In_channel.with_open_text path In_channel.input_all in
  let _, out = Miniml.Driver.feed (Miniml.Driver.initial ()) src in
  if out <> "" then print_endline out
;;

let () =
  match Sys.argv with
  | [| _ |] ->
    print_endline
      "MiniML REPL — type an expression or a let/type declaration; Ctrl-D to exit.";
    repl (Miniml.Driver.initial ())
  | [| _; file |] -> run_file file
  | _ ->
    prerr_endline "usage: miniml [FILE]";
    exit 2
;;
