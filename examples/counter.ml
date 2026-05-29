(* Mutable references and sequencing (v1.0). *)

let counter = ref 0

(* mutate the shared cell and return its new value; body is a parenthesized
   sequence (`e1; e2`) *)
let bump = fun n -> (counter := !counter + n; !counter)

let a = bump 5
let b = bump 3
let total = !counter
