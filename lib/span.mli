(** Source locations.

    A {!t} is a half-open range of source text, carried by every AST node so that
    diagnostics can point a caret at the exact offending span. Positions come from
    the lexer (via [Lexing.position]) and are merged as the parser builds larger
    nodes. *)

type pos =
  { line : int (** 1-based line number *)
  ; col : int (** 0-based column (characters since the start of the line) *)
  ; off : int (** 0-based byte offset into the whole source *)
  }

type t =
  { lo : pos (** inclusive start *)
  ; hi : pos (** exclusive end *)
  }

(** A sentinel span for synthesized nodes that have no source location. *)
val dummy : t

(** [merge a b] is the span reaching from the start of [a] to the end of [b]. *)
val merge : t -> t -> t

(** Build a span from a pair of lexer positions (menhir's [$startpos]/[$endpos],
    or any [Lexing.position] pair). *)
val of_lexing : Lexing.position -> Lexing.position -> t

(** Render a span as e.g. ["line 2, cols 4-9"], for human-readable messages. *)
val to_string : t -> string
