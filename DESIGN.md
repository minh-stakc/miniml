# Design notes

An engineering journal for MiniML: the decisions that shaped the implementation,
the alternatives I weighed and rejected, the bugs that taught me something, and
what I would do next. The reference docs in [`docs/`](docs/) explain *how* each
algorithm works; this file explains *why the code looks the way it does*.

## Decisions and trade-offs

### Union-find type variables, not substitutions

Algorithm W is usually presented with explicit substitutions composed at every
step. I represent a type variable instead as a mutable cell that is either
`Unbound (id, level)` or `Link t`, and unification sets links destructively;
`repr` is union-find *find* with path compression.

The trade-off is real. Destructive mutation is harder to reason about, and I gave
up cheap backtracking (a constraint solver that wanted to try-and-undo would have
to copy). In exchange unification is near-constant amortized instead of repeatedly
allocating and applying substitution maps, and — the deciding factor — the
mutable representation is what makes the level trick below cheap. Functional
substitution maps would have been tidier to test but would have obscured exactly
the part of the system that is interesting to get right.

### Rémy levels for generalization, not an environment scan

The textbook rule "generalize the variables not free in the environment" means
scanning the whole typing environment at each `let`. Instead every unbound
variable records the `let`-nesting level at which it was born, and on leaving a
`let` I generalize exactly the variables whose level is *strictly* greater than
the current one.

The subtlety that took the longest to get right: unification must **lower** a
variable's level (take the `min`) whenever it is linked beneath where it was
created. `occurs_adjust` does the occurs check and the level-lowering in a single
pass for that reason. Miss it and generalization quantifies a variable that is
still reachable from an outer scope, which is unsound. The adversarial test
`let_mono_level` (`fun x -> let y = x in (y, y)` must infer `'a -> 'a * 'a`, not
`'a -> 'b * 'c`) exists specifically to catch a regression here, and it did catch
one during development. These are the 30 lines I was most careful to get right.

### Two match compilers, kept side by side

The first match compiler tested each clause in turn — a correct test-then-bind
*sequence*. The second compiles the whole clause matrix into a decision *tree*
(Maranget, ML 2008) so that each sub-value is tested at most once on any path.

I kept both, behind a `strategy` flag, rather than deleting the naive one. Two
reasons. First, the naive compiler became a third independent back-end: the
property tests assert the evaluator, the naive VM, and the decision-tree VM all
agree on 500 generated programs, so the optimization can't silently change a
result. Second, having the simple version to diff against is what made the
optimizing version safe to trust. The payoff is measured, not asserted: on the
test corpus the tree emits **20% fewer comparison sites (35 → 28)** and is never
worse on any single case (`dune exec bench/bench.exe` reproduces the table).

### One value representation, shared by both back-ends

The tree-walking evaluator and the bytecode VM produce the *same* `Value.t`. That
lets a single structural `Value.equal` drive differential testing: when the two
disagree, the bug is in the compiler or the VM, never in a translation between
two value types. The cost is that neither back-end gets a value form tuned to its
own convenience. It is easily worth it — two independently written back-ends
agreeing on ~1,500 generated programs per run is the strongest evidence in the
project that both are correct.

### List environments, not arrays

The VM's environment is a `Value.t list`: cons to extend, index to access. An
array or a flat register file would make `ACCESS` O(1) instead of O(depth). I
chose the list for clarity, and because closure capture is then a single pointer
copy. Since variables are lowered to de Bruijn indices at compile time, there is
no name lookup at runtime either way. A production VM would switch to arrays and
measure; I noted it under "next" rather than pretending the list is optimal.

### Records as rows, reusing the inference machinery

A record type is `TRecord row`, where a row is a chain of
`TRowExtend (label, field_type, rest)` terminated by either `TRowEmpty` (a closed
record) or a type variable (an open one). Field access `r.x` unifies `r` against
`{ x : 'a; .. }` with a *fresh row variable* for the tail, so an accessor is
row-polymorphic: `fun r -> r.x` infers `{ x : 'a; .. } -> 'a` and works on any
record that has an `x`.

The reason this is a small feature and not a second type system: row variables
are ordinary type variables in row position. Generalization, instantiation, the
occurs check, and level demotion all apply to them unchanged. The only genuinely
new code is `rewrite_row`, which exposes a label in a row, extending an open tail
with a fresh variable when the label is not yet present. I rejected a separate
constraint solver for records precisely because it would not have inherited
let-generalization for free.

### Interfaces first

Every hand-written module has an `.mli` that re-exports its public types and hides
its helpers — the unification internals, the bytecode assembler, the match-matrix
machinery. This is the ordinary convention in production OCaml: the signature is
the contract, hiding the helpers keeps a refactor from silently widening the API,
and the compiler enforces it. Where the Base/Core conventions fit naturally — the
central type named `t`, an `_exn` partner for a raising variant — I followed them,
but I did not add unused `_exn` aliases just to look the part; the interface
describes what the code actually offers.

## What broke, and how I found out

- **A missing level demotion over-generalized.** Before `occurs_adjust` lowered
  levels on linking, a variable created inside a `let` could be generalized even
  though it was still reachable from an outer binding. The symptom was a type that
  was *too* polymorphic. `let_mono_level` turns that symptom into a failing test.

- **Records introduced two grammar conflicts.** Adding `ref e`, `!e`, and field
  access `e.x` produced a 2-conflict ambiguity: `ref r.x` could parse as
  `ref (r.x)` or `(ref r).x`. I found them by running `menhir --explain` and
  reading the generated `.conflicts` file, and resolved them by parsing the
  argument of `ref`/`!` as an *atom*, which fixes the reading to `!r.x = (!r).x`.
  The grammar is back to 0 shift/reduce and 0 reduce/reduce conflicts.

- **The pretty-printer's variable names depended on evaluation order.** Type
  variables are renamed to `'a`, `'b`, … by first appearance. An early version
  built the two sides of an arrow with `^`, whose argument evaluation order is
  unspecified in OCaml, so the names could come out swapped. Fixed by sequencing
  the recursive calls with explicit `let` bindings before concatenating.

- **A multi-agent adversarial review found 9 real defects.** Of ~38 candidate
  findings, 9 held up against ML semantics and were fixed, the most serious being
  a soundness hole (non-linear patterns such as `(x, x)` were accepted, which lets
  a value's type be two things at once) and a value-restriction level-demotion
  gap. Each fix is locked with a regression test, and none changed a
  previously-passing test.

## What's next

- An array-backed VM environment for O(1) variable access, with a benchmark to
  justify the change rather than assume it.
- `when` guards and or-patterns; the decision tree already has most of the
  structure or-patterns need.
- A bytecode verifier / typed bytecode, so the "the VM never traps on well-typed
  input" property is checked structurally and not only by testing.
- Short-circuiting `&&` / `||` (currently strict, kept consistent across both
  back-ends) as an explicit evaluation-order change.
- An editor integration that surfaces inferred types inline.
