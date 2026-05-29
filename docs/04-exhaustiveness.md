# 04 — Exhaustiveness & Redundancy

`lib/exhaust.ml` implements Maranget's **usefulness** algorithm ("Warnings for
pattern matching", JFP 2007) to answer two questions about every `match`:

- **exhaustiveness** — do the patterns cover every possible value? If not, it
  produces a **witness**: a concrete unmatched pattern (`None`, `_ :: _`,
  `(false, _)`, …).
- **redundancy** — is any clause unreachable (subsumed by the clauses above it)?

## Usefulness

The single primitive is

```
useful P q  =  is there a value matched by the pattern vector q but by no row of the matrix P?
```

with these corollaries:

- a match whose pattern column is `P` is **exhaustive** iff `useful P [_]` is
  false (the wildcard vector adds nothing);
- clause `i` is **redundant** iff `useful P[0..i-1] [pᵢ]` is false.

`useful` recurses on the first column (`lib/exhaust.ml`):

```
useful P (q1 :: qs):
  q1 is a constructor c(r…):  useful (specialize c P) (r… ++ qs)
  q1 is a wildcard:
     Σ = head constructors in column 0 of P
     if Σ is a complete signature:   ∃ c∈Σ. useful (specialize c P) (wildcards(c) ++ qs)
     else:                            useful (default P) qs
useful P []:  P has no rows           (* base case: width 0 *)
```

- **`specialize c`** keeps the rows headed by `c` (exposing its sub-patterns) and
  the wildcard rows (expanding the head to the right number of wildcards), and
  drops rows headed by a different constructor.
- **`default`** keeps only the wildcard rows, dropping the head column.

## Where the type comes from

Maranget's algorithm needs the **complete constructor set** of the column's type
to decide the "is Σ complete?" branch. MiniML recovers that from the constructors
that *appear* in the column (`full_ctor_set`), plus the ADT environment for
user constructors:

| a head present in the column | the type, and its full set |
|---|---|
| `[]` or `::` | `list` → `{[], ::}` |
| `true` / `false` | `bool` → `{true, false}` |
| `()` | `unit` → `{()}` |
| a tuple pattern | the (single) tuple constructor — always complete |
| an `int` literal | `int` → infinite, **never** complete |
| a user constructor `C` | look up `C`'s type in `denv`, take all its constructors |

A column of only wildcards has an empty signature (never complete) — but then the
algorithm takes the `default` branch and never needs the type. So **no separate
type information has to be threaded in**: if a value can reach a column, either a
constructor names the type or a wildcard already covers it.

## Witnesses, in lock-step

The implementation returns the witness directly rather than a boolean, so witness
construction splits on exactly the same complete/incomplete test as the
usefulness decision. This matters: if witness generation and usefulness ever
disagreed about completeness, the "counterexample" could be a value that is
actually matched. Concretely, in the incomplete-signature branch the witness
prepends `witness_head`:

- a **missing constructor** of a finite type, applied to wildcards
  (`None`, `Some _`, `_ :: _`, `Blue`, `Node (_, _, _)`); or
- a plain `_` for an `int` column or an all-wildcard column ("some other value").

## Integration

`Infer.check_match` runs `Exhaust.check` on every `match` during inference and
records a `warning` (non-fatal) for a non-exhaustive match (with its witness) or
for each redundant clause. The driver/REPL prints them; a non-exhaustive match is
a warning, not an error, mirroring OCaml.

## Files

- `lib/exhaust.ml` — `useful`, `specialize`, `default`, `full_ctor_set`, witness
  construction, and the `check` entry point.
- `test/test_exhaust.ml` — verdicts, witnesses, redundancy across built-in and
  user types, plus the inference-integration check.
