(* Polymorphic list functions — every type below is inferred, no annotations. *)

let rec map = fun f -> fun xs ->
  match xs with
  | [] -> []
  | h :: t -> f h :: map f t

let rec filter = fun p -> fun xs ->
  match xs with
  | [] -> []
  | h :: t -> if p h then h :: filter p t else filter p t

let rec foldl = fun f -> fun acc -> fun xs ->
  match xs with
  | [] -> acc
  | h :: t -> foldl f (f acc h) t

let sum = foldl (fun a -> fun b -> a + b) 0

(* x is even iff x - (x / 2) * 2 = 0  (MiniML has no mod operator) *)
let is_even = fun x -> x - x / 2 * 2 = 0

let nums = [1; 2; 3; 4; 5; 6]
let doubled = map (fun x -> x * 2) nums
let evens = filter is_even nums
let total = sum nums
