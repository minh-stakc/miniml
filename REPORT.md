# MiniML — Project Report

A statically-typed, ML-family programming language implemented from scratch in
OCaml: a complete pipeline from source text to a value executed on a custom
bytecode virtual machine, with full type inference, exhaustiveness checking, and
property-tested type soundness.

## By the numbers

| | |
|---|---|
| Implementation (compiler + VM + REPL) | **~3,400 lines** of OCaml; 15 library modules, each with an `.mli` interface, plus an ocamllex lexer and a menhir parser |
| Tests | **184** cases, ~1,100 lines (unit, differential, property-based, and CLI golden snapshots) |
| Documentation | ~900 lines across 10 design docs, plus a study guide and an engineering journal |
| Bytecode VM | **31** instructions (one a compile-time label marker), iterative loop, proper tail calls |
| Match compiler | decision tree emits **20% fewer comparison sites** than the naive strategy on the test corpus |
| Parser | **0** shift/reduce & reduce/reduce conflicts (menhir) |
| Releases | **10 tagged milestones** (`v0.1` → `v1.1`) |
| External runtime deps | **none** (OCaml stdlib only) |

Largest modules: `infer.ml` (576, the type inferencer), `compile.ml` (305),
`exhaust.ml` (265).

## What it is

```
source ─lex─▶ tokens ─parse─▶ AST ─infer (Algorithm W)─▶ typed AST
   ├─ exhaustiveness check (Maranget)
   └─ compile (de Bruijn) ─▶ bytecode ─▶ stack VM ─▶ value
                                  ▲                       │
                       reference evaluator ─▶ value ──────┘  (differential oracle)
```

The language (**MiniML**) is a real ML, not a toy lambda calculus: `let`/`let rec`
with mutual recursion, curried first-class functions and closures, algebraic data
types, pattern matching, lists and tuples, mutable references, row-polymorphic
records, and let-polymorphism. Every type is inferred with **zero annotations**.

## Engineering highlights

- **Hindley-Milner type inference (Algorithm W).** Mutable **union-find** type
  variables with **Rémy levels** for efficient let-generalization (no
  environment scan), occurs check, instantiation, and the **value restriction**.
  Infers the principal type of every program; rejects every ill-typed one.
- **Pattern-match exhaustiveness & redundancy** via Maranget's usefulness
  algorithm, with constructive **counterexample witnesses** (`Some _`, `_ :: _`,
  `Blue`, …), the feature OCaml is known for and most student interpreters lack.
- **Optimizing decision-tree match compiler** (Maranget, ML 2008). Matches
  compile to a decision tree that tests each sub-value at most once per path,
  rather than re-testing shared structure clause by clause. The naive compiler is
  kept as a second back-end and the two are checked for agreement, so the
  optimization is provably behaviour-preserving; it emits **20% fewer comparison
  sites** on the test corpus (`dune exec bench/bench.exe`).
- **Row-polymorphic records.** A field accessor infers an open row, e.g.
  `fun r -> r.x : { x : 'a; .. } -> 'a`, so it applies to any record with the
  field. Row variables are ordinary type variables in row position, so they reuse
  generalization, instantiation, and the occurs check unchanged.
- **Bytecode compiler + stack VM.** This is a *compiler*, not just a tree-walker:
  de Bruijn-indexed environments, closure conversion, mutually-recursive closures
  (knot-tied by back-patching), and **proper tail calls** — a 100,000-iteration
  tail-recursive loop runs in *constant* stack space (asserted by a test). The VM
  loop is iterative, so deep recursion never overflows the host stack.
- **Mutable references** make the value restriction load-bearing: the classic
  polymorphic-reference unsoundness is correctly rejected.
- **REPL + diagnostics.** Caret-underlined type errors, occurs-check errors, and
  non-exhaustive-match warnings with source spans.

## Testing & correctness methodology

Correctness is the headline, defended five ways:

1. **Unit tests** per layer (lexer, parser, inference, exhaustiveness, VM).
2. **Differential testing.** The bytecode VM and an independent reference
   evaluator must produce identical results on every program; two independent
   implementations agreeing is strong evidence both are right. For matches there
   is a *third* back-end (the naive match compiler), so all three must agree.
3. **Property-based soundness.** A type-directed generator builds **1,000**
   well-typed programs per run and asserts the practical *progress + preservation*
   property: a well-typed program never reaches a stuck (type-error) state in the
   VM, and the VM agrees with the evaluator. A second 500-case property checks the
   two match compilers against the evaluator.
4. **Hand-written adversarial inference tests** that target the *rejection* path a
   property generator cannot reach (over-generalization, the occurs check, the
   monomorphism of lambda/`let rec` variables, the value restriction).
5. **Cram golden snapshots** of the CLI, run as a gate by `dune runtest` and
   updated with `dune promote`, pinning the end-to-end output (inferred types,
   values, and diagnostics).

The implementation was also put through a **multi-agent adversarial code review**.
Of ~38 candidate findings, **9 genuine defects** were confirmed against ML
semantics and fixed: most notably a **type-soundness hole** (non-linear patterns
such as `(x, x)` were accepted, yielding a value/type mismatch), two crash paths,
and a value-restriction level-demotion gap. Each is locked with a regression test,
and the fixes changed zero previously-passing tests.

The design decisions behind all of this, and the alternatives rejected, are
written up in [`DESIGN.md`](DESIGN.md).

## Milestones (tagged releases)

`v0.1` lexer + parser · `v0.2` type inference · `v0.3` exhaustiveness ·
`v0.4` reference evaluator · `v0.5` bytecode compiler + VM ·
`v0.6` property-tested soundness + CI · `v0.7` REPL + diagnostics ·
`v0.7.1` review hardening · `v1.0` mutable references + value restriction ·
`v1.1` decision-tree match compiler, row-polymorphic records, `.mli` interfaces,
and cram snapshots.

## Possible extensions

With rationale in [`DESIGN.md`](DESIGN.md): an array-backed VM environment for
O(1) variable access, `when` guards and or-patterns, a bytecode verifier, and an
editor integration that surfaces inferred types.

## Reproducing the results

```sh
opam install . --deps-only --with-test
dune build      # the compiler + VM
dune test       # all 184 tests (unit, differential, 1,500-case property, cram)
dune exec bench/bench.exe   # the match-compiler comparison-site table
dune exec miniml            # the REPL
dune exec miniml -- examples/tree.ml
```
