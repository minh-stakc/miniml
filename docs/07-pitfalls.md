# 07 — Pitfalls

The correctness traps in this kind of project, the **symptom** each produces, and
where MiniML handles it. These are the things to be able to explain.

## Type inference

### 1. Forgetting to lower levels during unification
`occurs_adjust` (`lib/infer.ml`) does *two* jobs when linking a variable to a
type: the occurs check **and** lowering every reachable variable's level to at
most the linked variable's. Drop the level-lowering (`min`) and you get **silent
unsoundness**: a variable that has escaped into an outer binding keeps its high
level and is wrongly generalized later. The bug is invisible on most programs —
it needs a term where a variable is shared between a `let` body and the
environment. *Symptom:* a program that should be rejected type-checks, or a value
is given a more polymorphic type than is sound.

### 2. Generalizing with `>=` instead of `>`
`generalize` quantifies variables with `level > current_level`. Using `>=`
generalizes a variable that is still free in the environment. *Symptom:*
`fun x -> let y = x in (y, y)` infers `'a -> 'b * 'c` instead of `'a -> 'a * 'a`
— the test `let_mono_level` in `test_infer.ml` catches exactly this.

### 3. Missing occurs check
Unifying `'a` with `'a -> 'b` builds a cyclic type. *Symptom:* `fun x -> x x`
either loops forever (in `unify` or when printing the type) or crashes. MiniML
raises `Occurs_check`; `test_infer.ml` asserts it.

### 4. Generalizing a recursive binding too early
In `let rec`, the recursive names must stay **monomorphic while their own
right-hand sides are elaborated** (HM has no polymorphic recursion). Generalize
them before and `let rec f = fun x -> (f 1, f true)` wrongly type-checks.
*Symptom:* polymorphic-recursion programs accepted (unsound w.r.t. HM).

### 5. Generalizing a non-value (value restriction)
Without the `is_value` gate, adding mutable references later makes the classic
polymorphic-reference hole reappear. *Symptom (with refs):* `let r = ref [] in
…` is given `∀a. a list ref` and can be written at one type and read at another.

## Exhaustiveness

### 6. Witness generation out of step with usefulness
The constructive `useful` must branch on the *same* complete/incomplete signature
test as the boolean decision. If they diverge, the reported "counterexample" can
be a value the match actually covers. *Symptom:* a bogus non-exhaustive warning
whose witness is, in fact, matched. MiniML keeps them in one function.

## Bytecode VM

### 7. Tail calls that push a frame
If `TAILAPPLY` pushed a return frame like `APPLY`, tail recursion would grow the
frame stack linearly. *Symptom:* a long tail-recursive loop exhausts memory (or,
with a recursive interpreter loop, overflows the host stack). MiniML's
`test_vm.ml` runs 100000 iterations and asserts `max_frame_depth ≤ 5`.

### 8. Recursive closures that don't see themselves
`let rec` closures must capture an environment that already contains them.
`CLOSUREREC` allocates the closures, then **back-patches** each one's `venv` to
the shared recursive environment. Forget the back-patch and a recursive call
finds an unbound variable. *Symptom:* `Type_trap "environment access out of
range"` (or a wrong value) on the first recursive call.

### 9. Wrong operand order for non-commutative primitives
`PRIM` pops the second operand first, then the first (`compile` pushes them in
source order). Get it backwards and `10 - 3` yields `-7`. The differential tests
(VM vs. evaluator) catch this immediately, since the evaluator computes
`10 - 3 = 7`.

### 10. Restoring the environment after a non-tail `let`/`match`
A `let`/`match` in non-tail position grows `env` with locals that must be dropped
(`ENDLET`) once it produces its value; in tail position the enclosing `RETURN`
restores `env` wholesale, so no `ENDLET` is emitted. Mixing these up corrupts
later variable indices. *Symptom:* wrong variable values after a `let`/`match`
expression; again caught by the differential tests.

## How they're all caught

- **Inference traps (1–5):** the hand-written `infer-adversarial` suite — it
  targets the rejection path and specific polymorphic types, which a
  well-typed-by-construction generator cannot reach.
- **Exhaustiveness (6):** `test_exhaust.ml` pins the exact witnesses.
- **VM traps (7–10):** the VM-vs-evaluator **differential** tests plus the
  1000-case soundness property (`test_soundness.ml`), where any `Type_trap` on
  well-typed input is a failure.
