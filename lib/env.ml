(** The typing environment: a persistent map from program variable names to their
    type schemes. Lambda- and pattern-bound variables are stored as monomorphic
    schemes ([qvars = []]); [let]-bound variables may be polymorphic. *)

module M = Map.Make (String)

type t = Types.scheme M.t

let empty : t = M.empty
let add (x : string) (s : Types.scheme) (e : t) : t = M.add x s e
let find (x : string) (e : t) : Types.scheme option = M.find_opt x e
