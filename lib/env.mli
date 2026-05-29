(** The typing environment: a persistent map from program variable names to their
    type schemes. Lambda- and pattern-bound variables are stored as monomorphic
    schemes; [let]-bound variables may be polymorphic. *)

type t

val empty : t

(** [add x scheme env] binds [x] to [scheme], shadowing any previous binding. *)
val add : string -> Types.scheme -> t -> t

(** [find x env] is the scheme bound to [x], or [None] if [x] is unbound. *)
val find : string -> t -> Types.scheme option
