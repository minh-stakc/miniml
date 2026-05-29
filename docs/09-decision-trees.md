# 09 — Decision-Tree Match Compilation

MiniML has **two** pattern-match compilers, and a test proves they agree on
every program. This doc explains the optimizing one and why having both is the
point.

## Two strategies

`Compile.strategy` selects how a `match` lowers to bytecode:

- **`Naive`** (`Compile.naive_match`) — each clause is an independent
  test-then-bind sequence; a failed test jumps to the next clause. Simple and
  obviously correct, but it re-examines shared prefixes: in
  `match xs with [] -> … | x :: y :: _ -> … | x :: _ -> …` it tests `xs`'s
  constructor once per clause.
- **`Decision_tree`** (the default; `Compile.tree_match` over
  `Decision_tree.build`) — builds a single decision tree from the whole clause
  matrix, so each sub-value (an *occurrence*) is tested **at most once on any
  path**. Clauses that agree on an outer constructor share that test and branch
  only on what differs.

## The algorithm (Maranget, ML 2008)

`Decision_tree.build` works on a clause matrix — rows of (pattern-vector,
action, accumulated bindings) — over a list of *occurrences* (paths from the
scrutinee, `int list`, e.g. `[0; 1]` = "field 0, then the tail"):

```
build rows:
  rows = []                          -> Fail                     (* runtime match failure *)
  first row all wildcards/vars       -> Leaf (action, bindings)  (* first match wins *)
  otherwise:
    pick a column j with a constructor in the first row
    Σ = head constructors in column j
    for each c ∈ Σ:  branch (test c, build (specialize c rows))
    if Σ is a complete signature:  no default
    else:                          default = build (default rows)
    -> Switch (occurrence_j, branches, default)
```

- **`specialize c`** keeps rows headed by `c` (replacing that column with `c`'s
  sub-patterns at deeper occurrences) and wildcard rows (expanded to fresh
  wildcards), dropping rows headed by a different constructor.
- **`default`** keeps the wildcard rows (dropping the tested column).
- **Single-constructor columns** (tuples, `unit`) are *irrefutable*: no test is
  emitted, the fields are simply exposed at deeper occurrences.
- **Variable bindings travel with the tree**: when a wildcard/variable column is
  specialized or defaulted, a `PVar x` records `x ↦ occurrence`. A `Leaf` carries
  the full binding set for its path, so lowering a leaf just pushes each bound
  occurrence (`ACCESS scrutinee; FIELD …`) and `LET`s it.

## Completeness without the type environment

Deciding whether to emit a default branch needs the type's full constructor set.
The compiler is deliberately kept free of the typing environment, so it
recognizes only **built-in** completeness (`bool` = {true,false}, `list` =
{[], ::}, `unit`, tuples) and otherwise emits a `Fail` default. For a *user* ADT
match this means a sound—but, on an exhaustive match, technically redundant—
default. That default is unreachable for programs that passed the
exhaustiveness check, and threading the type environment in to drop it is a
noted, easy future optimization. (Sharing of tests — the main win — does not
depend on it.)

## Why keep both — the guardrail

An optimizing compiler backend is exactly where subtle bugs hide. Rather than
trust the decision tree, MiniML keeps the naive compiler and
**differentially tests the two against each other and the reference evaluator**:
`test/test_match.ml` asserts `evaluator = naive-VM = decision-tree-VM` on a
corpus that stresses shared prefixes and pattern depths, and on **500 generated
well-typed programs** per run. Two independent strategies plus an independent
evaluator agreeing is strong evidence all three are correct — and it turns the
riskiest change in the project into its most defensible one.

## Files

- `lib/decision_tree.ml` — the tree builder (pure, over patterns).
- `lib/compile.ml` — `tree_match` lowers the tree; `naive_match` is the baseline;
  `strategy` selects.
- `test/test_match.ml` — the two-strategy + evaluator agreement guardrail.
