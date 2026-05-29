# 01 — Overview

MiniML turns source text into a value in five stages, each a separate module so
each can be read, tested, and explained on its own.

```
source string
   │  Lexer        (lib/lexer.mll, ocamllex)       characters -> tokens
   ▼
tokens
   │  Parser       (lib/parser.mly, menhir)        tokens -> surface AST
   ▼
Ast.program / Ast.expr            (lib/ast.ml)
   │  Infer        (lib/infer.ml)                  Hindley-Milner, Algorithm W
   ▼
typed AST  (+ inferred types)
   │  Exhaust      (lib/exhaust.ml)                pattern-match coverage check
   ▼
   │  Compile      (lib/compile.ml)                typed AST -> bytecode
   ▼                                               (de Bruijn lowering happens here)
Bytecode.code      (lib/bytecode.ml)
   │  VM           (lib/vm.ml)                      execute on a stack machine
   ▼
Value.t            (lib/value.ml)
        ▲
        │  a reference tree-walking evaluator (lib/eval.ml) produces the same
        │  Value.t, and tests assert the two agree (differential testing).
```

## Module map

| Module | Role | Milestone |
|--------|------|-----------|
| `Span` | source positions + ranges for diagnostics | v0.1 ✅ |
| `Lexer` | ocamllex lexer: characters → tokens | v0.1 ✅ |
| `Parser` | menhir grammar: tokens → AST | v0.1 ✅ |
| `Ast` | surface syntax (every node carries a `Span.t`) | v0.1 ✅ |
| `Pretty` | precedence-aware printer for the AST, inferred types, and schemes | v0.1 ✅ |
| `Types` | type representation: union-find type vars + levels, schemes | v0.2 |
| `Env` | typing environment (variable → type scheme) | v0.2 |
| `Infer` | Algorithm W: unify, occurs check, generalize, instantiate | v0.2 |
| `Exhaust` | Maranget usefulness algorithm: exhaustiveness + redundancy | v0.3 |
| `Value` | runtime values shared by the VM and the reference evaluator | v0.4 |
| `Eval` | reference tree-walking interpreter (the differential-testing oracle) | v0.4 |
| `Bytecode` | the VM instruction set | v0.5 |
| `Compile` | typed AST → bytecode: de Bruijn lowering, closures, tail calls, match plans | v0.5 |
| `Decision_tree` | Maranget decision-tree match compilation (the optimizing match strategy) | v1.1 |
| `Vm` | the stack machine | v0.5 |
| `Errors` | caret-underlined diagnostics | v0.7 |
| `Driver` | glue: string → typecheck / run / eval | v0.7 |

Each hand-written module has an `.mli` interface that re-exports its public types
and hides its helpers. Later features extend these modules rather than adding
pipeline stages: mutable references (v1.0) and row-polymorphic records (v1.1) live
in `Types`/`Infer`/`Value`/`Compile`, and `Decision_tree` is an alternative
match-compilation strategy selected by `Compile`.

## Building

A `dune` + `opam` toolchain with `menhir` is assumed (see the repo README).

```sh
opam install . --deps-only --with-test
dune build            # compile the library + CLI
dune test             # alcotest + qcheck suites
dune exec miniml -- FILE   # parse/typecheck/run a program
```

## Design philosophy

This is a teaching/portfolio implementation, so two principles win ties:

1. **Correctness over features.** The type checker must be sound; the VM must
   never execute a well-typed program into a stuck state. These properties are
   tested directly (hand-written adversarial cases plus property tests).
2. **Readable over clever.** Each algorithm is implemented in its
   textbook-recognizable form and documented in `docs/`, so the implementation
   can be defended line by line.
