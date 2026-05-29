# MiniML

A small, statically-typed **ML-family language implemented in OCaml** — with full
**Hindley-Milner type inference**, pattern-match **exhaustiveness checking**, a
**bytecode compiler**, and a **stack VM** that executes the bytecode.

MiniML infers every type with **zero annotations**, rejects ill-typed programs
*before* they run, and then compiles them to bytecode it runs itself. Type
soundness is **property-tested** (progress + preservation) and cross-checked
against a reference interpreter.

> Status: in active development. See [Project status](#project-status) for what
> is implemented vs. planned, and the per-milestone git tags (`v0.1` …).

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
- **pattern matching** (wildcard / variable / literal / constructor / tuple /
  cons, nested) with exhaustiveness + redundancy warnings
- **let-polymorphism** (with the value restriction)
- arithmetic, comparison, and boolean operators; a `print_int` primitive

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

<!-- A recorded REPL session is added at the v0.7 milestone. -->

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
| [`STUDY-GUIDE.md`](STUDY-GUIDE.md) | per-topic key ideas, likely questions, and "make it yours" exercises |

## Project status

| Milestone | Tag | State |
|-----------|-----|-------|
| Lexer + parser + AST + pretty-printer | `v0.1` | ✅ done (0 grammar conflicts) |
| Hindley-Milner type inference | `v0.2` | ✅ done (union-find + levels) |
| Pattern-match exhaustiveness | `v0.3` | ✅ done (Maranget + witnesses) |
| Reference evaluator | `v0.4` | ✅ done (differential-testing oracle) |
| Bytecode compiler + stack VM | `v0.5` | ✅ done (proper tail calls) |
| Property-tested soundness + CI | `v0.6` | planned |
| REPL + error spans + examples | `v0.7` | planned |
| Mutable refs + value restriction | `v1.0` | planned (optional) |

### Not done yet / honest limitations

- (filled in as the project progresses — e.g. records, `when` guards, modules,
  an optimizing decision-tree match compiler, an LSP, algebraic effects)

## License

MIT — see [LICENSE](LICENSE).
