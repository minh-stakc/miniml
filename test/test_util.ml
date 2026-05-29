(** Shared helpers for the test suites. *)

let parse_expr (s : string) : Miniml.Ast.expr =
  Miniml.Parser.expr_main Miniml.Lexer.token (Lexing.from_string s)
;;

let parse_prog (s : string) : Miniml.Ast.program =
  Miniml.Parser.program Miniml.Lexer.token (Lexing.from_string s)
;;
