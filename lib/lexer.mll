{
(* ocamllex lexer for MiniML. Produces the tokens declared in parser.mly.

   Tracks source positions (via [Lexing.new_line] on every newline) so that
   menhir's [$startpos]/[$endpos] yield accurate spans. Supports nested
   [(* ... *)] comments via a depth counter. *)

open Parser

exception Lexing_error of string

let keyword_table : (string, token) Hashtbl.t = Hashtbl.create 32
let () =
  List.iter
    (fun (k, v) -> Hashtbl.replace keyword_table k v)
    [ "let", LET; "rec", REC; "and", AND; "in", IN; "fun", FUN
    ; "if", IF; "then", THEN; "else", ELSE; "match", MATCH; "with", WITH
    ; "type", TYPE; "of", OF; "true", TRUE; "false", FALSE; "not", NOT
    ; "ref", REF ]
}

let digit   = ['0'-'9']
let int     = digit+
let lower   = ['a'-'z' '_']
let upper   = ['A'-'Z']
let idchar  = ['a'-'z' 'A'-'Z' '0'-'9' '_' '\'']
let ident   = lower idchar*
let uident  = upper idchar*
let white   = [' ' '\t']+
let newline = ('\r' '\n') | '\n' | '\r'

rule token = parse
  | white         { token lexbuf }
  | newline       { Lexing.new_line lexbuf; token lexbuf }
  | "(*"          { comment 1 lexbuf; token lexbuf }
  | int as s      { try INT (int_of_string s)
                    with _ -> raise (Lexing_error ("integer literal out of range: " ^ s)) }
  | "->"          { ARROW }
  | ":="          { COLONEQ }
  | "::"          { COLONCOLON }
  | "!"           { BANG }
  | "<="          { LE }
  | ">="          { GE }
  | "<>"          { NEQ }
  | "&&"          { ANDAND }
  | "||"          { OROR }
  | "("           { LPAREN }
  | ")"           { RPAREN }
  | "["           { LBRACKET }
  | "]"           { RBRACKET }
  | ","           { COMMA }
  | ";"           { SEMI }
  | "|"           { PIPE }
  | "="           { EQUAL }
  | "+"           { PLUS }
  | "-"           { MINUS }
  | "*"           { STAR }
  | "/"           { SLASH }
  | "<"           { LT }
  | ">"           { GT }
  | "_"           { UNDERSCORE }
  | "'" (ident as s) { TYVAR s }
  | ident as s    { match Hashtbl.find_opt keyword_table s with Some t -> t | None -> IDENT s }
  | uident as s   { UIDENT s }
  | eof           { EOF }
  | _ as c        { raise (Lexing_error (Printf.sprintf "unexpected character %C" c)) }

and comment depth = parse
  | "(*"    { comment (depth + 1) lexbuf }
  | "*)"    { if depth > 1 then comment (depth - 1) lexbuf }
  | newline { Lexing.new_line lexbuf; comment depth lexbuf }
  | eof     { raise (Lexing_error "unterminated comment") }
  | _       { comment depth lexbuf }
