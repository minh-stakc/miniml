(** Diagnostics rendering. *)

(** [format_at ~src span msg] renders [msg] under the source line picked out by
    [span], with a caret underline:
    {v
    2 | let x = 1 + true
                    ^^^^
    this expression has type bool but type int was expected
    v}
    If the span has no real location, just [msg] is returned. *)
val format_at : src:string -> Span.t -> string -> string
