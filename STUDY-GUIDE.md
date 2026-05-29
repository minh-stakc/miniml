# Study Guide

How to *own* MiniML — built so it can be explained and defended in depth, not
just demoed. For each hard topic: the key idea, the questions you should expect,
where it lives in the code, and an exercise to make it yours by changing it.

Work through these with the code open. Each "make it yours" exercise has a
predictable failure mode — breaking it on purpose and watching the tests catch it
is the fastest way to understand why the code is the way it is.

---

## 1. Hindley-Milner inference — `lib/infer.ml`, `lib/types.ml`

**Key idea.** Walk the AST minting fresh type variables; **unify** to enforce
constraints; **generalize** a `let`-bound type into a `∀`-scheme; **instantiate**
schemes with fresh variables per use. Type variables are mutable union-find
nodes; the **occurs check** rejects infinite types. Generalization decides *which*
variables are safe to quantify using **Rémy levels** instead of scanning the
environment.

**Expect to be asked.**
- What is unification, concretely, and why is it union-find? (`repr` is *find*;
  `r := Link t` is *union*.)
- What does the occurs check prevent, and what happens without it? (Infinite type;
  `fun x -> x x`.)
- What are levels and why are they correct? Why `level > current_level`, strictly?
- Walk `let id = fun x -> x in (id 1, id true)` and `fun x -> let y = x in (y, y)`
  — why is one polymorphic and the other not? (The level test.)
- Why no polymorphic recursion? Why the value restriction?

**Read.** `docs/03-type-inference.md`, then `unify`/`occurs_adjust`,
`generalize`/`instantiate`, and `infer_bindings` in `lib/infer.ml`.

**Make it yours.**
- Change `level > current_level` to `>=` in `generalize`; run `dune test`. The
  `let_mono_level` case fails — explain why.
- Delete the `if id = id' then raise Occurs_internal` line; run the `occurs` test
  (it will hang or fail). Explain.
- Re-derive `occurs_adjust`'s level-lowering on paper for a term where a variable
  escapes a `let`.

---

## 2. Exhaustiveness — `lib/exhaust.ml`

**Key idea.** Maranget's `useful P q`: is there a value matched by `q` but no row
of `P`? Exhaustiveness = the wildcard vector is **not** useful; redundancy = a row
is not useful against the rows above it. The constructive version returns a
**witness**, splitting on the same complete/incomplete signature test as the
boolean decision.

**Expect to be asked.**
- How do you know a column's type to test signature completeness? (From the
  constructors present, plus the ADT environment — never threaded separately.)
- How is `int` handled? (Infinite → never complete → default branch.)
- How is the witness built, and why must it stay in step with `useful`?

**Read.** `docs/04-exhaustiveness.md`, then `useful`/`specialize`/`default` and
`witness_head` in `lib/exhaust.ml`.

**Make it yours.** Add `when` guards to a clause and decide what they do to
exhaustiveness (hint: a guarded clause cannot be assumed to match — it must not
reduce the matrix). Sketch the change to `collect`/`check`.

---

## 3. Bytecode compiler + stack VM — `lib/compile.ml`, `lib/vm.ml`

**Key idea.** Compile the typed AST to an environment stack machine. Variables
are de Bruijn indices (`ACCESS`). Closures capture the environment; `let rec`
ties the knot with `CLOSUREREC` (mutating each closure's captured env). A `~tail`
flag yields `TAILAPPLY` (no frame) for tail calls. `match` compiles to a
test-then-bind decision sequence.

**Expect to be asked.**
- How are closures represented and captured? How does `let rec` see itself?
- What makes a tail call a tail call here, and how do you know it's constant
  space? (`TAILAPPLY` pushes no frame; the `max_frame_depth ≤ 5` test.)
- How does the VM avoid overflowing OCaml's own stack on deep recursion? (The
  loop is iterative.)
- How does `match` compile, and why split testing from binding?

**Read.** `docs/05-bytecode-vm.md`, then `compile_let_rec`, the tail handling in
`compile`, `compile_match`, and the `APPLY`/`TAILAPPLY`/`RETURN`/`CLOSUREREC`
cases of `Vm.run`.

**Make it yours.** Make `TAILAPPLY` behave like `APPLY` (push a frame); run
`dune test`. The tail-call test fails on `max_frame_depth`. Explain the
space difference.

---

## 4. Soundness & differential testing — `test/test_soundness.ml`, `test/test_vm.ml`

**Key idea.** Two independent back-ends (VM and tree-walking evaluator) must agree
on every program. A type-directed generator produces well-typed programs; the
property asserts none of them hit a VM `Type_trap` and that VM = evaluator —
practical progress + preservation.

**Expect to be asked.**
- What does a `Type_trap` on type-checked input *mean*? (A soundness bug.)
- Why can't the property generator find inference bugs like over-generalization?
  (It only builds well-typed terms; it never exercises rejection — hence the
  hand-written adversarial suite.)

**Read.** `docs/06-testing.md`, then the generator and `property` in
`test_soundness.ml`.

**Make it yours.** Add a deliberately-unsound generalization (`>=`) and watch
whether the *property* catches it (it won't — only the hand-written tests do).
That contrast is the point.

---

## Quick map

| Want to understand… | Open |
|---|---|
| the type representation | `lib/types.ml` |
| inference, the core | `lib/infer.ml` + `docs/03` |
| exhaustiveness | `lib/exhaust.ml` + `docs/04` |
| the compiler & VM | `lib/compile.ml`, `lib/vm.ml` + `docs/05` |
| how it's all kept honest | `test/` + `docs/06`, `docs/07` |
