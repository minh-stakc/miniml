(** Source locations.

    A {!t} is a half-open range of source text, carried by every AST node so
    that type errors, non-exhaustive-match warnings, and parse errors can point
    a caret at the exact offending span. Positions are produced by the lexer
    (via [Lexing.position]) and merged as the parser builds larger nodes. *)

type pos =
  { line : int (* 1-based line number *)
  ; col : int (* 0-based column (chars since start of line) *)
  ; off : int (* 0-based byte offset into the whole source *)
  }

type t =
  { lo : pos (* inclusive start *)
  ; hi : pos (* exclusive end *)
  }

let dummy_pos = { line = 0; col = 0; off = 0 }
let dummy = { lo = dummy_pos; hi = dummy_pos }

(** [merge a b] is the span reaching from the start of [a] to the end of [b]. *)
let merge (a : t) (b : t) : t = { lo = a.lo; hi = b.hi }

let pos_of_lexing (p : Lexing.position) : pos =
  { line = p.Lexing.pos_lnum
  ; col = p.Lexing.pos_cnum - p.Lexing.pos_bol
  ; off = p.Lexing.pos_cnum
  }
;;

(** Build a span from menhir's [$startpos]/[$endpos] (or any pair of lexer
    positions). *)
let of_lexing (s : Lexing.position) (e : Lexing.position) : t =
  { lo = pos_of_lexing s; hi = pos_of_lexing e }
;;

let to_string (s : t) : string =
  if s.lo.line = s.hi.line
  then Printf.sprintf "line %d, cols %d-%d" s.lo.line s.lo.col s.hi.col
  else
    Printf.sprintf "line %d col %d - line %d col %d" s.lo.line s.lo.col s.hi.line s.hi.col
;;
