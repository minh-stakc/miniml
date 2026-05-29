(* A polymorphic binary tree, with size and sum folds. *)

type 'a tree =
  | Leaf
  | Node of 'a tree * 'a * 'a tree

let rec size = fun t ->
  match t with
  | Leaf -> 0
  | Node (l, _, r) -> size l + 1 + size r

let rec sum_tree = fun t ->
  match t with
  | Leaf -> 0
  | Node (l, v, r) -> sum_tree l + v + sum_tree r

let t = Node (Node (Leaf, 1, Leaf), 2, Node (Leaf, 3, Node (Leaf, 4, Leaf)))
let node_count = size t
let total = sum_tree t
