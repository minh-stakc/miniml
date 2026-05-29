(** The glue that turns a line of source into a printable response, used by both
    the REPL and the file runner.

    A {!state} accumulates the type-declaration environment, the typing
    environment, and the bindings declared so far, so each fresh input is
    typechecked and run in the context of everything entered before it. *)

(** REPL/session state. Opaque: thread it from {!initial} through {!feed}. *)
type state

(** A fresh, empty session. *)
val initial : unit -> state

(** [feed state input] typechecks and evaluates one chunk of source (a
    declaration or expression), returning the updated state and the text to
    display — an inferred type and value, any warnings, or a caret-underlined
    error. Never raises: errors are rendered into the returned string. *)
val feed : state -> string -> state * string
