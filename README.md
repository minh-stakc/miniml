# MiniML

[![CI](https://github.com/minh-stakc/miniml/actions/workflows/ci.yml/badge.svg)](https://github.com/minh-stakc/miniml/actions/workflows/ci.yml)
![OCaml](https://img.shields.io/badge/OCaml-5.2-orange)
![tests](https://img.shields.io/badge/tests-184%20passing-brightgreen)
![parser conflicts](https://img.shields.io/badge/menhir%20conflicts-0-brightgreen)
![license](https://img.shields.io/badge/license-MIT-blue)

A small, statically-typed **ML-family language implemented in OCaml** — with full
**Hindley-Milner type inference**, pattern-match **exhaustiveness checking**, a
**bytecode compiler**, and a **stack VM** that executes the bytecode.

MiniML infers every type with **zero annotations**, rejects ill-typed programs
*before* they run, and then compiles them to bytecode it runs itself. Type
soundness is **property-tested** (progress + preservation) and cross-checked
against a reference interpreter.

**By the numbers:** ~3,400 lines of OCaml across 15 library modules (each with an
`.mli` interface) plus an ocamllex lexer and a menhir parser · 184 tests (unit,
differential, 1,500-case property-based, and CLI golden snapshots) · a
31-instruction stack VM with proper tail calls · 0 parser conflicts · 10 tagged
releases. Design rationale in [`DESIGN.md`](DESIGN.md); full write-up in
[`REPORT.md`](REPORT.md).

```
source ──lex──▶ tokens ──parse──▶ surface AST
   │
   ├─ infer  (Algorithm W: union-find unification + level-based generalization)  ──▶ typed AST
   │
   ├─ exhaust (Maranget usefulness matrix: exhaustiveness + redundancy + witnesses)
   │
   └─ compile (de Bruijn lowering ─▶ bytecode) ──▶  stack VM  ──▶  value
                                                       ▲                │
                                         reference evaluator ──▶ value ─┘
                                              (differential testing oracle)
```

## Why this project

Hindley-Milner inference and a bytecode compiler are the canonical "build a real
type system and a real compiler" problem — and writing it *in OCaml* makes the
implementation itself evidence of OCaml fluency. The hard parts (unification, the
occurs check, let-generalization with levels, exhaustiveness, closures, proper
tail calls) are each documented in [`docs/`](docs/) so the design can be read,
understood, and defended in detail.

## Algorithm W in five lines

> Algorithm W infers the **principal** (most general) type of an expression with
> no annotations. It walks the AST, minting a **fresh type variable** for each
> unknown and **unifying** types as constraints arise (a function's parameter
> with its argument, the two branches of an `if`, …). At each `let` it
> **generalizes** the bound expression's type into a polymorphic scheme over the
> variables introduced *inside* that `let` — tracked here efficiently by Rémy
> **levels** rather than scanning the environment — and **instantiates** schemes
> with fresh variables at every use. The **occurs check** during unification
> rejects infinite types (e.g. `fun x -> x x`). The result is the most general
> type, guaranteed.

The full, teachable walkthrough — with worked examples and the level annotations
— is in [`docs/03-type-inference.md`](docs/03-type-inference.md).

## The language

```ml
(* zero annotations — every type below is inferred *)
let rec map = fun f -> fun xs ->
  match xs with
  | []      -> []
  | x :: tl -> f x :: map f tl

let rec fold = fun f -> fun acc -> fun xs ->
  match xs with
  | []      -> acc
  | x :: tl -> fold f (f acc x) tl

type 'a tree = Leaf | Node of 'a tree * 'a * 'a tree

let rec sum_tree = fun t ->
  match t with
  | Leaf          -> 0
  | Node (l, v, r) -> sum_tree l + v + sum_tree r
```

- `let` / `let rec` with `and` for mutual recursion
- first-class **curried functions** + closures
- `int`, `bool`, `unit`, tuples, lists (`[]`, `::`, `[a; b; c]`)
- **user-defined algebraic data types** (`type 'a option = None | Some of 'a`)
- **records with row-polymorphic inference**: `{ x = 1; y = true }`, field access
  `r.x`, and open rows (`{ x : 'a; .. }`) so an accessor works on any matching record
- **pattern matching** (wildcard / variable / literal / constructor / tuple /
  cons, nested) with exhaustiveness + redundancy warnings, compiled by an
  optimizing **decision tree** that tests each sub-value at most once per path
- **let-polymorphism** (with the value restriction)
- **mutable references** (`ref` / `!` / `:=`) and `;` sequencing
- arithmetic, comparison, and boolean operators

## Build & run

Requires an OCaml ≥ 4.14 switch with `dune` and `menhir` (and `alcotest` /
`qcheck` / `qcheck-alcotest` for the tests).

```sh
opam install . --deps-only --with-test
dune build           # build the compiler + VM
dune test            # unit + differential + property (soundness) tests
dune exec miniml     # start the REPL
dune exec miniml -- examples/map.ml   # run a program
```

### A REPL session

Each phrase is lexed, parsed, type-inferred, exhaustiveness-checked, compiled to
bytecode, and run on the VM — and the inferred type and value are printed:

```
$ dune exec miniml
miniml> type 'a option = None | Some of 'a
type option defined
miniml> let id = fun x -> x
id : 'a -> 'a = <fun>
miniml> (id 1, id true)
- : int * bool = (1, true)
miniml> let rec fact = fun n -> if n = 0 then 1 else n * fact (n - 1)
fact : int -> int = <fun>
miniml> fact 10
- : int = 3628800

miniml> let getx = fun r -> r.x
getx : { x : 'a; .. } -> 'a = <fun>
miniml> (getx { x = 1; y = true }, getx { x = 9 })
- : int * int = (1, 9)

miniml> match Some 5 with Some x -> x
- : int = 5
1 | match Some 5 with Some x -> x
    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Warning: this pattern matching is not exhaustive; an unmatched value: None

miniml> fun x -> x x
1 | fun x -> x x
             ^^^
cannot construct the infinite type 'a

miniml> 1 + true
1 | 1 + true
    ^^^^^^^^
this expression has type int but type bool was expected
```

Runnable programs live in [`examples/`](examples/) (`dune exec miniml -- examples/lists.ml`).

## Documentation

The internals are documented to teach, not just to describe:

| Doc | Topic |
|-----|-------|
| [`docs/01-overview.md`](docs/01-overview.md) | the pipeline & module map |
| [`docs/02-lexer-parser.md`](docs/02-lexer-parser.md) | ocamllex/menhir, the precedence ladder, conflict resolution |
| [`docs/03-type-inference.md`](docs/03-type-inference.md) | ⭐ union-find, levels, unify + occurs check, generalize/instantiate, value restriction |
| [`docs/04-exhaustiveness.md`](docs/04-exhaustiveness.md) | Maranget's usefulness algorithm + witness generation |
| [`docs/05-bytecode-vm.md`](docs/05-bytecode-vm.md) | the instruction set, closures, recursive closures, proper tail calls |
| [`docs/06-testing.md`](docs/06-testing.md) | unit / differential / type-directed property testing |
| [`docs/07-pitfalls.md`](docs/07-pitfalls.md) | the correctness traps and the symptom each bug produces |
| [`docs/08-refs-value-restriction.md`](docs/08-refs-value-restriction.md) | mutable references and why the value restriction is needed |
| [`docs/09-decision-trees.md`](docs/09-decision-trees.md) | ⭐ Maranget decision-tree match compilation, and the cost it saves |
| [`docs/10-records-rows.md`](docs/10-records-rows.md) | ⭐ row-polymorphic records on top of the existing inferencer |
| [`DESIGN.md`](DESIGN.md) | engineering journal: decisions, rejected alternatives, bugs that taught me something |
| [`STUDY-GUIDE.md`](STUDY-GUIDE.md) | per-topic key ideas, likely questions, and "make it yours" exercises |

## Project status

| Milestone | Tag | State |
|-----------|-----|-------|
| Lexer + parser + AST + pretty-printer | `v0.1` | ✅ done (0 grammar conflicts) |
| Hindley-Milner type inference | `v0.2` | ✅ done (union-find + levels) |
| Pattern-match exhaustiveness | `v0.3` | ✅ done (Maranget + witnesses) |
| Reference evaluator | `v0.4` | ✅ done (differential-testing oracle) |
| Bytecode compiler + stack VM | `v0.5` | ✅ done (proper tail calls) |
| Property-tested soundness + CI | `v0.6` | ✅ done (1000-case qcheck) |
| REPL + error spans + examples | `v0.7` | ✅ done |
| Mutable refs + value restriction | `v1.0` | ✅ done |
| Decision-tree match compiler · row-polymorphic records · `.mli` interfaces · cram snapshots | `v1.1` | ✅ done |

### Not done yet / honest limitations

- **`&&` / `||` are strict** (both operands evaluated), not short-circuiting. This
  is a deliberate simplification kept consistent between the VM and the evaluator.
- **No `when` guards, or-patterns, modules, or strings.** Records exist, but only
  with construction and field access (no functional update or record patterns).
- **Parse errors** are reported without a caret (type errors are).
- **`=` on functions returns `false`** rather than raising as OCaml does;
  closures are treated as opaque and never equal.
- **The reference evaluator** (the differential-testing oracle) uses host-stack
  recursion, so it can stack-overflow on extremely deep *non-tail* recursion
  where the iterative bytecode VM still succeeds; differential tests use bounded
  programs.
- Possible extensions, with rationale, are listed in [`DESIGN.md`](DESIGN.md):
  an array-backed VM environment, `when` guards and or-patterns, a bytecode
  verifier, and an editor integration that surfaces inferred types.

## License

MIT — see [LICENSE](LICENSE).
