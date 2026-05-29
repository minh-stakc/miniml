# 05 — Bytecode Compiler & Stack VM

After type-checking, a program is compiled (`lib/compile.ml`) to bytecode
(`lib/bytecode.ml`) and executed on a stack VM (`lib/vm.ml`). This is what makes
MiniML a *compiler*, not just an interpreter — and it is differentially tested
against the reference evaluator (every result must agree).

## The machine

An **environment machine**. The VM holds four registers:

- `pc` — the program counter into the instruction array;
- `stack` — the operand stack (`Value.t list`);
- `env` — the current environment (`Value.t list`); variables are de Bruijn
  indices, read with `ACCESS i = List.nth env i`;
- `frames` — a return stack of `{ ret_pc; ret_env }`.

The execution loop is **iterative** (`while`), so a deeply-recursive *MiniML*
program never overflows *OCaml's* call stack: MiniML activation records live on
`frames`, not on the host stack.

## Variables and closures

Names are resolved to indices at compile time against a `cenv` (a name list that
mirrors the runtime `env`). A lambda `fun x -> body`:

```
CLOSURE l_body ; JUMP l_after ; l_body: <body compiled under (x :: cenv), in tail position> ; l_after:
```

`CLOSURE` captures the **whole** current environment into `VClosVM { code; venv }`.
When applied, the callee runs with `env = arg :: venv`, which matches the
compile-time `x :: cenv`. So free-variable capture is automatic.

### `let rec` ties the knot

`CLOSUREREC [l₁; …; lₙ]` builds *n* closures over **one shared** environment that
includes the closures themselves:

```
rec_env = [cl₁; …; clₙ] @ env      (* the recursive bindings, then the outer env *)
each clᵢ.venv ← rec_env            (* back-patch: each closure can see all siblings *)
env          ← rec_env             (* the body of the let rec runs with them in scope *)
```

The mutation of `venv` is the knot: every recursive (and mutually-recursive)
function can reach itself and its siblings. This is the question every reviewer
asks; the code spells the back-patch out rather than hiding it.

## Application, return, and proper tail calls

A `~tail` flag is threaded through compilation:

- `APPLY` (non-tail): push `{ ret_pc = pc; ret_env = env }`, then jump into the
  closure with `env = arg :: venv`. The body ends with `RETURN`, which pops the
  frame and restores `pc`/`env`.
- `TAILAPPLY` (tail): identical **except it pushes no frame** — it reuses the
  caller's pending frame. A self-recursive tail loop therefore keeps `frames` at
  constant depth. (`test/test_vm.ml` runs a 100000-step loop and asserts the max
  frame depth stays ≤ 5; the partial-application frame is the only transient.)

Tail position is computed structurally: a function body is tail; the branches of
an `if`, the body of a `let`, and clause bodies of a `match` inherit the
position; the scrutinee, condition, and function/argument sub-expressions never
do. An application in tail position becomes `TAILAPPLY` (with no trailing
`RETURN`); everything else computes a value and the enclosing `RETURN` ends the
frame.

## Compiling `match`

Each clause compiles to a **decision sequence**, split into two phases so that a
failed clause has changed nothing:

1. **Test phase** — for each constructor in the pattern, push the relevant
   sub-value (by an `ACCESS scrutinee; FIELD …` path) and run a `TEST`; on
   mismatch, jump to the next clause. `TEST` covers ints, bools, `[]`, `::`, and
   data constructors (by name). Tuples and wildcards need no test.
2. **Bind phase** — once the whole pattern matched, push each pattern variable's
   value (again by its `FIELD` path from the scrutinee) and `LET` them, then
   compile the clause body. The last clause's failure target is `MATCHFAIL`
   (a trap, unreachable for an exhaustive match).

This is a simple, correct scheme; the optimal decision trees of Maranget's *other*
paper (sharing tests across clauses) are noted as future work.

## Values, primitives, and traps

Runtime values are the shared `Value.t` (so the VM and evaluator are comparable).
Arithmetic, comparison, and equality go through the **same** `Eval.eval_binop`
the evaluator uses, guaranteeing identical results (and identical division-by-zero
behaviour). The VM raises `Type_trap` on a genuinely stuck state — applying a
non-function, projecting a field of a non-aggregate, an `if` on a non-boolean.
**On type-checked input these are unreachable**, which is exactly what the
soundness property (v0.6) asserts.

## The assembler

`compile` emits an instruction list using integer **labels** for jump targets and
`LABEL` markers. `assemble` makes two passes: first it records each label's
address (its index once `LABEL`s are dropped), then it rewrites every
`JUMP`/`JUMPIFNOT`/`CLOSURE`/`CLOSUREREC`/`TEST` target to that address and emits
the final `instr array`.

## Files

- `lib/bytecode.ml` — the instruction set.
- `lib/compile.ml` — AST → bytecode (closures, tail calls, match plan, assembler).
- `lib/vm.ml` — the execution loop and typed traps.
- `test/test_vm.ml` — differential tests vs. the evaluator + the tail-call test.
