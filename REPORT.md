# MiniML — Project Report

A statically-typed, ML-family programming language implemented from scratch in
OCaml: a complete pipeline from source text to a value executed on a custom
bytecode virtual machine, with full type inference, exhaustiveness checking, and
property-tested type soundness.

## By the numbers

| | |
|---|---|
| Implementation (compiler + VM + REPL) | **~2,500 lines** of OCaml, 16 modules |
| Tests | **146** cases, ~950 lines, 10 suites |
| Documentation | ~1,000 lines across 8 design docs + a study guide |
| Bytecode VM | **34** instructions, iterative loop, proper tail calls |
| Parser | **0** shift/reduce & reduce/reduce conflicts (menhir) |
| Releases | **9 tagged milestones** (`v0.1` → `v1.0`) |
| External runtime deps | **none** (OCaml stdlib only) |

Largest modules: `infer.ml` (512 — the type inferencer), `exhaust.ml` (264),
`compile.ml` (246).

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
types, pattern matching, lists and tuples, mutable references, and
let-polymorphism — every type inferred with **zero annotations**.

## Engineering highlights

- **Hindley-Milner type inference (Algorithm W).** Mutable **union-find** type
  variables with **Rémy levels** for efficient let-generalization (no
  environment scan), occurs check, instantiation, and the **value restriction**.
  Infers the principal type of every program; rejects every ill-typed one.
- **Pattern-match exhaustiveness & redundancy** via Maranget's usefulness
  algorithm, with constructive **counterexample witnesses** (`Some _`, `_ :: _`,
  `Blue`, …) — the feature OCaml is known for and most student interpreters lack.
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

Correctness is the headline, defended four ways:

1. **Unit tests** per layer (lexer, parser, inference, exhaustiveness, VM).
2. **Differential testing** — the bytecode VM and an independent reference
   evaluator must produce identical results on every program (two independent
   implementations agreeing is strong evidence both are right).
3. **Property-based soundness** — a type-directed generator builds **1,000**
   well-typed programs per run and asserts the practical *progress + preservation*
   property: a well-typed program never reaches a stuck (type-error) state in the
   VM, and the VM agrees with the evaluator.
4. **Hand-written adversarial inference tests** that target the *rejection* path a
   property generator cannot reach (over-generalization, the occurs check, the
   monomorphism of lambda/`let rec` variables, the value restriction).

The implementation was then put through a **multi-agent adversarial code review**.
Of ~38 candidate findings, **9 genuine defects** were confirmed against ML
semantics and fixed — most notably a **type-soundness hole** (non-linear patterns
such as `(x, x)` were accepted, yielding a value/type mismatch), two crash paths,
and a value-restriction level-demotion gap — each locked with a regression test.
The fixes changed zero previously-passing tests.

## Milestones (tagged releases)

`v0.1` lexer + parser · `v0.2` type inference · `v0.3` exhaustiveness ·
`v0.4` reference evaluator · `v0.5` bytecode compiler + VM ·
`v0.6` property-tested soundness + CI · `v0.7` REPL + diagnostics ·
`v0.7.1` review hardening · `v1.0` mutable references + value restriction.

## Possible extensions

A typed bytecode, an optimizing decision-tree match compiler, OCaml-5 algebraic
effects, and an LSP that surfaces inferred types in the editor.

## Reproducing the results

```sh
opam install . --deps-only --with-test
dune build      # the compiler + VM
dune test       # all 146 tests (unit + differential + 1000-case soundness)
dune exec miniml            # the REPL
dune exec miniml -- examples/tree.ml
```
