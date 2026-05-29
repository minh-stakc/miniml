# Changelog

## v1.1

- Optimizing **decision-tree match compiler** (Maranget, ML 2008) alongside the
  original naive strategy, selectable by a flag. The two are checked for
  agreement against the evaluator over the corpus and 500 generated programs; the
  tree emits 20% fewer comparison sites on the corpus (`bench/bench.exe`).
- **Records with row-polymorphic inference**: record literals, field access, and
  open rows (`{ x : 'a; .. }`), so a field accessor works on any record with that
  field.
- An **`.mli` interface for every module**, hiding internal helpers behind the
  public surface.
- **Cram golden snapshots** for the CLI (`dune runtest` / `dune promote`), and a
  cost guardrail asserting the decision tree never regresses below the naive
  compiler.
- `DESIGN.md` engineering journal.

## v1.0

- Mutable references (`ref` / `!` / `:=`) and the **value restriction**, which
  correctly rejects the classic polymorphic-reference unsoundness.

## v0.7.1

- Hardening from a multi-agent adversarial review: 9 confirmed defects fixed,
  including a soundness hole (non-linear patterns such as `(x, x)` were accepted)
  and a value-restriction level-demotion gap. Each is locked with a regression
  test.

## v0.7

- REPL and file runner; caret-underlined diagnostics for type errors, the occurs
  check, and non-exhaustive matches; runnable examples.

## v0.6

- Type-directed property testing: a generator builds well-typed programs and
  asserts practical progress + preservation (the VM never reaches a stuck state
  and agrees with the evaluator). GitHub Actions CI.

## v0.5

- Bytecode compiler and stack VM: de Bruijn environments, closure conversion,
  mutually-recursive closures, and proper tail calls (constant stack on deep tail
  recursion). Differential testing against the reference evaluator.

## v0.4

- Reference tree-walking evaluator, built before the VM to serve as the
  differential-testing oracle.

## v0.3

- Pattern-match exhaustiveness and redundancy checking via Maranget's usefulness
  algorithm, with constructive counterexample witnesses.

## v0.2

- Hindley-Milner type inference (Algorithm W) with union-find unification, Rémy
  levels for let-generalization, the occurs check, and instantiation.

## v0.1

- Lexer (ocamllex), parser (menhir, 0 conflicts), surface AST, and a
  precedence-aware pretty-printer.
