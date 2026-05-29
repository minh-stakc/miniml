The CLI runs a file through the whole pipeline (lex, parse, Hindley-Milner
inference, exhaustiveness checking, bytecode compilation, then the stack VM)
and prints each top-level binding's inferred type scheme and value.

Polymorphism is principal: `id` and `compose` get their most general types, and
a recursive `length` typechecks and runs on the VM.

  $ cat > demo.ml <<'EOF'
  > let id = fun x -> x
  > let compose = fun f -> fun g -> fun x -> f (g x)
  > let rec length = fun xs -> match xs with [] -> 0 | h :: t -> 1 + length t
  > let n = length [10; 20; 30]
  > EOF
  $ miniml demo.ml
  id : 'a -> 'a = <fun>
  compose : ('a -> 'b) -> ('c -> 'a) -> 'c -> 'b = <fun>
  length : 'a list -> int = <fun>
  n : int = 3

Records are row-polymorphic: a bare field access infers an open row `{ x : 'a; .. }`,
so the same accessor works on any record that has the field.

  $ cat > records.ml <<'EOF'
  > let p = { x = 1; y = true }
  > let getx = fun r -> r.x
  > let a = getx { x = 42; tag = 0 }
  > let b = getx { x = 7 }
  > EOF
  $ miniml records.ml
  p : { x : int; y : bool } = { x = 1; y = true }
  getx : { x : 'a; .. } -> 'a = <fun>
  a : int = 42
  b : int = 7

User-declared algebraic data types, with recursion and pattern matching:

  $ cat > tree.ml <<'EOF'
  > type 'a tree = Leaf | Node of 'a tree * 'a * 'a tree
  > let rec size = fun t -> match t with Leaf -> 0 | Node (l, _, r) -> 1 + size l + size r
  > let s = size (Node (Node (Leaf, 1, Leaf), 2, Leaf))
  > EOF
  $ miniml tree.ml
  type tree defined
  size : 'a tree -> int = <fun>
  s : int = 2
