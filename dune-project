(lang dune 3.6)

(name miniml)

(generate_opam_files true)

(using menhir 2.1)

(cram enable)

(source
 (github minh-stakc/miniml))

(authors "Nathan Hoang")

(maintainers "Nathan Hoang")

(license MIT)

(package
 (name miniml)
 (synopsis
  "A statically-typed ML-family language: HM type inference, a bytecode compiler, and a stack VM")
 (description
  "MiniML is a small statically-typed functional language implemented in OCaml. It performs full Hindley-Milner type inference (Algorithm W with union-find unification and level-based let-generalization), pattern-match exhaustiveness and redundancy checking, compiles the typed program to bytecode, and executes it on a stack VM. Type soundness (progress + preservation) is property-tested with qcheck and cross-checked against a reference tree-walking evaluator.")
 (depends
  (ocaml
   (>= 4.14))
  dune
  (menhir
   (>= 2.1))
  (alcotest :with-test)
  (qcheck :with-test)
  (qcheck-alcotest :with-test))
 (tags
  ("compiler" "type-inference" "hindley-milner" "bytecode" "ocaml")))
