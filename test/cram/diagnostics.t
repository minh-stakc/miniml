Type errors are reported with a caret underlining the offending span.

  $ cat > type_error.ml <<'EOF'
  > 1 + true
  > EOF
  $ miniml type_error.ml
  1 | 1 + true
      ^^^^^^^^
  this expression has type int but type bool was expected

The occurs check rejects self-application, which would need an infinite type.

  $ cat > occurs.ml <<'EOF'
  > fun x -> x x
  > EOF
  $ miniml occurs.ml
  1 | fun x -> x x
               ^^^
  cannot construct the infinite type 'a

A non-exhaustive match is reported as a warning with a concrete witness (a
value the patterns fail to cover), while still compiling and running.

  $ cat > partial.ml <<'EOF'
  > match [1] with h :: t -> h
  > EOF
  $ miniml partial.ml
  - : int = 1
  1 | match [1] with h :: t -> h
      ^^^^^^^^^^^^^^^^^^^^^^^^^^
  Warning: this pattern matching is not exhaustive; an unmatched value: []

A list whose elements disagree is rejected at the element type.

  $ cat > list_clash.ml <<'EOF'
  > 1 :: [true]
  > EOF
  $ miniml list_clash.ml
  1 | 1 :: [true]
      ^^^^^^^^^^^
  this expression has type int list but type bool list was expected
