# 08 — Mutable References & the Value Restriction

`v1.0` adds mutable state — `ref e`, `!e`, `e1 := e2`, and `;` sequencing — which
is what makes the **value restriction** load-bearing rather than dormant.

## Surface and types

| form | type | notes |
|------|------|-------|
| `ref e` | `'a -> 'a ref` (applied: `e : t` ⟹ `t ref`) | allocates a cell |
| `!e` | `'a ref -> 'a` | dereference |
| `e1 := e2` | `'a ref -> 'a -> unit` | assignment; result is `unit` |
| `e1; e2` | `e1 : unit`, result `e2`'s type | sequencing |

`ref` is a keyword; `!` is a tight prefix; `:=` is low-precedence right-associative
(`r := a || b` is `r := (a || b)`). Sequencing is allowed at top level and inside
parentheses, so a side-effecting body is written `let r = ref 0 in (r := 1; !r)`.

Runtime: a new value `VRef of Value.t ref`, shared by the evaluator and VM; three
instructions `MKREF` / `DEREF` / `ASSIGN`. `=` on references is structural on
their contents (matching OCaml).

## Why the value restriction matters now

Generalizing the type of an arbitrary expression is unsound once mutable cells
exist. The classic hole:

```ml
let r = ref [] in   (* if r : ∀a. a list ref ... *)
r := [1];           (*   ...store an int list... *)
r := [true]         (*   ...then a bool list — and a reader gets the wrong type *)
```

MiniML's checker takes the **value restriction**: only *syntactic values*
(variables, literals, lambdas, constructors of values) are generalized
(`Infer.is_value`). `ref []` is an application, **not** a value, so `r` gets a
single monomorphic (weak) type. The first `r := [1]` fixes that type to
`int list ref`; the `r := [true]` then fails to unify — **rejected**, exactly as
it should be. `test/test_refs.ml` pins both this and the function-reference
variant (`let r = ref (fun x -> x) in (r := (fun x -> x + 1); !r true)`).

A subtlety found in review and fixed: declining to generalize is not enough — the
non-value's type variables must also be **level-demoted** to the surrounding
level (`Infer.demote`), or an enclosing `let` could re-generalize them through an
alias (`let g = b in (g 1, g true)`). With the demotion, that program is correctly
rejected too. See [docs/03-type-inference.md] and [docs/07-pitfalls.md].

## Example

```ml
let counter = ref 0
let bump = fun n -> (counter := !counter + n; !counter)
```

`bump : int -> int`, mutating the shared `counter` cell. (Because tail recursion
already runs in constant space and the VM loop is iterative, references compose
with everything else — closures, matches, recursion — with no special cases.)
