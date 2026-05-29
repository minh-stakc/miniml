# 06 — Testing

MiniML is tested at three levels, all run by `dune test` (alcotest + qcheck):

## 1. Unit tests, per layer

- **`test_parser.ml`** — golden precedence/associativity, parse→print
  idempotence, and parses-ok for comments/ADTs/recursion.
- **`test_infer.ml`** — principal types, the **adversarial** inference suite
  (below), and ADTs.
- **`test_exhaust.ml`** — exhaustiveness verdicts, witnesses, redundancy, and
  the inference-integration (warnings are surfaced).
- **`test_eval.ml`** — the reference evaluator on closed programs.
- **`test_vm.ml`** — see differential + tail calls below.

## 2. Differential testing (VM vs. evaluator)

The bytecode VM and the reference tree-walking evaluator share one value
representation (`Value.t`), so a single `Value.equal` compares them. `test_vm.ml`
runs a corpus of closed programs through **both** back-ends and asserts they
agree — closures, recursion, `map`/`fold`, ADTs, nested and cons patterns, mutual
recursion, higher-order composition. Two independent implementations agreeing is
strong evidence both are right.

It also asserts **proper tail calls**: `loop 100000 0` (a tail-recursive sum)
returns `5000050000` while `Vm.max_frame_depth` stays ≤ 5 — constant space.

(One asymmetry: the reference evaluator recurses on OCaml's own stack, so it can
overflow on *extremely deep non-tail* recursion where the iterative VM still
succeeds. The differential corpus uses bounded programs; this makes the VM the
*more* robust of the two, not less.)

## 3. Property-tested soundness (`test_soundness.ml`)

A **type-directed generator** builds expressions that are well-typed *by
construction*: it generates top-down from a target type (`int`/`bool` at the top,
functions/tuples/lists/`let`/`if`/`match` inside), so every leaf and combination
respects the types. It omits recursion and division, so every program terminates
cleanly.

The property over 1000 generated programs:

> a well-typed program type-checks, runs on the VM **without a `Type_trap`**, and
> the VM result equals the evaluator's.

A `Type_trap` (applying a non-function, a field of a non-block, an `if` on a
non-boolean, a non-exhaustive `MATCHFAIL`) on type-checked input is precisely a
**type-soundness violation** — practical *progress + preservation*. qcheck prints
the offending program if one is ever found.

### Why the adversarial inference tests are hand-written

A well-typed-by-construction generator can only build programs that *should*
type-check; it never exercises the **rejection** path or the level distinction.
The bugs that matter most in HM inference — over-generalization, a missing occurs
check, generalizing an environment variable — only show up when the checker is
asked to *reject* something, or to infer a *specific* polymorphic type. So those
are hand-written in `test_infer.ml` (`infer-adversarial`): `fun f -> (f 1, f
true)` must be rejected, `fun x -> x x` must fail the occurs check, `fun x -> let
y = x in (y, y)` must infer `'a -> 'a * 'a` (not `'a -> 'b * 'c`), and so on. See
[docs/03-type-inference.md] and [docs/07-pitfalls.md].

## CI

`.github/workflows/ci.yml` runs on Linux via `ocaml/setup-ocaml`:
`opam install . --deps-only --with-test`, `dune build @all`, `dune test`, and a
formatting check (`dune build @fmt` against a pinned `ocamlformat`). The code is
portable OCaml, so CI passes regardless of the developer's OS.
