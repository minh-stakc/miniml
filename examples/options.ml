(* The option type and a couple of total functions over it. *)

type 'a option =
  | None
  | Some of 'a

let map_opt = fun f -> fun o ->
  match o with
  | None -> None
  | Some x -> Some (f x)

let safe_div = fun a -> fun b -> if b = 0 then None else Some (a / b)

let r1 = safe_div 10 2
let r2 = safe_div 10 0
let r3 = map_opt (fun x -> x + 100) (safe_div 20 4)
