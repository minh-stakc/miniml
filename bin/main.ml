(* MiniML CLI.

   v0.1: parse a file (or stdin) and pretty-print the AST, to exercise the
   lexer/parser/pretty-printer end to end. This grows into a full REPL +
   type-checking + VM runner in later milestones. *)

let parse_channel (ic : in_channel) : Miniml.Ast.program =
  let src = In_channel.input_all ic in
  let lexbuf = Lexing.from_string src in
  Miniml.Parser.program Miniml.Lexer.token lexbuf
;;

let read_program () : Miniml.Ast.program =
  match Sys.argv with
  | [| _ |] -> parse_channel stdin
  | [| _; file |] -> In_channel.with_open_text file parse_channel
  | _ ->
    prerr_endline "usage: miniml [FILE]";
    exit 2
;;

let () =
  match read_program () with
  | prog ->
    print_string (Miniml.Pretty.program prog);
    print_newline ()
  | exception Miniml.Lexer.Lexing_error msg ->
    Printf.eprintf "lex error: %s\n" msg;
    exit 1
  | exception Miniml.Parser.Error ->
    prerr_endline "parse error";
    exit 1
;;
