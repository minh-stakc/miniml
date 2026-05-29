# 10 — Records & Row Polymorphism

MiniML has **structurally-typed records with row-polymorphic inference**:
`{ x = 1; y = true }` builds a record, `e.x` projects a field, and a function
that accesses a field works on **any** record that has it:

```
fun r -> r.x          : { x : 'a; .. } -> 'a
fun r -> (r.x, r.y)   : { x : 'a; y : 'b; .. } -> 'a * 'b
```

The `..` is a **row variable**: the unspecified rest of the record. One accessor
applies to records of different shapes:

```
let get_x = fun r -> r.x in (get_x { x = 1; y = 2 }, get_x { x = true; z = 5 })
  : int * bool
```

(OCaml's *records* are nominal; this row polymorphism mirrors OCaml's *object*
and *polymorphic-variant* rows — Rémy's approach — re-used here for records.)

## Types: rows reuse the type-variable machinery

A row is a type built from field extensions over a tail (`lib/types.ml`):

```ocaml
typ = … | TRecord of typ | TRowEmpty | TRowExtend of string * typ * typ
```

- `{ x : int; y : bool }` (closed) = `TRecord (x:int ; y:bool ; TRowEmpty)`.
- `{ x : int; .. }` (open) = `TRecord (x:int ; ρ)` where `ρ` is an ordinary
  `TVar` used in row position.

Because a row variable is just a `TVar`, **generalization and instantiation get
row polymorphism for free**: quantifying `ρ` makes the row polymorphic, and each
use instantiates a fresh row. The traversals (`occurs_adjust`, `generalize`,
`instantiate`, `Pretty.typ`) all gained row cases.

## Inference

- **Construction** `{ x = e1; y = e2 }`: a **closed** row of exactly those
  fields (`TRowEmpty` tail).
- **Access** `e.x`: unify `e`'s type with `{ x : 'a; ρ }` for fresh `'a`, `ρ` —
  an **open** row, hence row-polymorphic — and return `'a`.

## Row unification (`Infer.rewrite_row`)

The interesting part is unifying two rows, which must handle field reordering and
open tails. `unify` delegates to `rewrite_row row l ft`, which exposes label `l`
at the front of `row` and returns the remainder:

- `{ l : t' ; rest }` with the same `l` → unify `ft` with `t'`, return `rest`;
- `{ l' : t' ; rest }`, `l' ≠ l` → keep `l'`, recurse into `rest`;
- a **row variable** tail → extend it: `ρ := { l : ft ; ρ' }` (a fresh `ρ'`),
  return `ρ'` (with the usual occurs-check + level adjustment, so the level
  discipline is preserved);
- a **closed** tail (`TRowEmpty`) → the field is genuinely absent → type error.

So `{ x = 1 }.y` is rejected (the closed record has no `y`), and
`(fun r -> r.x + 1) { x = true }` is rejected (field type clash), while
accessing a present field on an open row just works.

## Runtime

A record value is `Value.VRecord of (string * Value.t) list` (shared by the
evaluator and VM; structural, order-independent equality). The VM gains two
instructions — `MKRECORD labels` (pop one value per label, build the record) and
`GETFIELD l` (project) — and field access at run time is by **name**, so the same
compiled accessor works across record shapes, exactly as the row-polymorphic type
promises. `test/test_records.ml` checks the types above and that the VM agrees
with the evaluator on construction, access, and nesting.

## Scope

Construction, access, and (via `!`) deref-then-project are supported. Record
*patterns* (`match r with { x; _ } -> …`) and functional update
(`{ r with x = e }`) are natural next steps left as future work; the
row-polymorphic core is the interesting part and is complete.

## Files

- `lib/types.ml` — `TRecord` / `TRowEmpty` / `TRowExtend`.
- `lib/infer.ml` — `rewrite_row` and the `ERecord` / `EField` rules.
- `lib/{value,eval,bytecode,compile,vm}.ml` — `VRecord`, `MKRECORD`, `GETFIELD`.
- `test/test_records.ml` — row-polymorphism typing + VM/evaluator agreement.
