# 03 — Type Inference (Algorithm W with levels)

This is the heart of MiniML and the part most worth being able to defend. The
implementation is `lib/infer.ml` (≈ 300 lines) over the type representation in
`lib/types.ml`. It infers the **principal** (most general) type of every
expression with **no annotations**, and rejects every ill-typed program.

## The type representation is union-find

```ocaml
type tvar = Unbound of int * level | Link of typ
and  typ  = TVar of tvar ref | TArrow of typ*typ | TTuple of typ list | TCon of string*typ list
```

A type variable is a *mutable* node. `Unbound (id, level)` is a representative (a
union-find root); `Link t` is a parent pointer to the type the variable was
unified with. `repr` is union-find **find** with path compression:

```ocaml
let rec repr t = match t with
  | TVar ({contents = Link t'} as r) -> let t'' = repr t' in r := Link t''; t''
  | _ -> t
```

Unifying two variables is union (`r := Link t`); querying a variable's current
type is find (`repr`). That framing is the first thing an interviewer asks about,
so it is front-and-centre.

## Levels: generalize without scanning the environment

Textbook Algorithm W generalizes a `let`-bound type by quantifying
`ftv(τ) \ ftv(Γ)` — the variables free in the type but not in the environment.
Computing `ftv(Γ)` means walking the whole environment. MiniML uses **Rémy's
levels** instead (`lib/types.ml`, `lib/infer.ml`):

- a global `current_level` counter starts at 0 and is incremented on entry to
  every `let` right-hand side (`enter_level` / `leave_level`);
- every fresh variable records `current_level` at birth;
- a variable may be generalized at a `let` **iff its level is strictly greater
  than the level surrounding that `let`** — i.e. it was created inside the
  right-hand side and did not escape into the surrounding context.

The level is a cheap, local proxy for "does this variable also appear in the
environment?". Keeping it accurate is unification's job.

## Unification = occurs check + level lowering

```ocaml
let rec unify_ t1 t2 =
  let t1 = repr t1 and t2 = repr t2 in
  if t1 == t2 then () else match t1, t2 with
  | TVar ({contents = Unbound (id, lvl)} as r), t
  | t, TVar ({contents = Unbound (id, lvl)} as r) ->
      occurs_adjust id lvl t;   (* occurs check + lower levels of t's vars *)
      r := Link t               (* union *)
  | TArrow (a1,b1), TArrow (a2,b2) -> unify_ a1 a2; unify_ b1 b2
  | TTuple xs, TTuple ys when … -> List.iter2 unify_ xs ys
  | TCon (n1,a1), TCon (n2,a2) when … -> List.iter2 unify_ a1 a2
  | _ -> raise Unify_internal
```

Before linking variable `id` (at level `lvl`) to a type `t`, `occurs_adjust`
walks `t` once and does **two** jobs:

```ocaml
let rec occurs_adjust id lvl t = match repr t with
  | TVar ({contents = Unbound (id', l')} as r) ->
      if id = id' then raise Occurs_internal;       (* (1) occurs check *)
      if l' > lvl then r := Unbound (id', lvl)      (* (2) lower the level *)
  | TArrow (a,b) -> occurs_adjust id lvl a; occurs_adjust id lvl b
  | TTuple ts | TCon (_,ts) -> List.iter (occurs_adjust id lvl) ts
  | TVar {contents = Link _} -> assert false
```

1. **Occurs check.** If `id` occurs inside `t`, linking would build an infinite
   type (`'a = 'a -> 'b`). Reject it. This is exactly what stops `fun x -> x x`.
2. **Level lowering** (the subtle one). Linking `id` to `t` makes every variable
   in `t` reachable from wherever `id` was reachable — including the enclosing
   environment, if `id` escaped there. So no variable in `t` may be generalized
   any "deeper" than `id`: lower each to `min(l', lvl)`. **Omitting this single
   `min` is the classic silent unsoundness bug** — the inferencer would
   generalize a variable that is actually still constrained elsewhere.

## Generalize and instantiate

```ocaml
let generalize t =                        (* call AFTER leave_level *)
  (* quantify unbound vars with level > current_level; strict > *)
  …
let instantiate {qvars; body} =           (* fresh copy of the quantified vars *)
  (* replace each qvar with a fresh var at current_level; share the rest *)
  …
```

Two easy-to-get-wrong details:

- **`generalize` runs after `leave_level`**, comparing against the level
  *outside* the let. The test is strict `>`: a variable at exactly the current
  level is reachable from the environment and must stay monomorphic.
- **`instantiate` shares non-quantified variables** (returns them as-is) and only
  freshens the quantified ones, so a scheme stays connected to the rest of the
  type graph.

## The typing rules that do the work

- **Lambda** (`infer` / `EFun`): the parameter is bound to a *bare monomorphic*
  variable (`dont_generalize`). This is why `fun f -> (f 1, f true)` is
  **rejected**: `f`'s single variable is unified with both `int -> _` and
  `bool -> _`.
- **`let x = e1 in e2`** (`infer_bindings`, non-recursive): `enter_level`,
  infer `e1`, `leave_level`, then `generalize` *iff the value restriction allows*
  it, and bind `x` to the resulting scheme. This is why `let id = fun x -> x in …`
  makes `id` polymorphic while the lambda case above does not.
- **`let rec … and …`**: bind every name to a fresh **monomorphic** variable,
  infer all right-hand sides against those, *then* generalize. Keeping the
  recursive names monomorphic during elaboration forbids polymorphic recursion
  (undecidable in HM) — so `let rec f = fun x -> (f 1, f true)` is **rejected**,
  while mutually-recursive `even`/`odd` type-check fine.
- **Constructors / patterns** (`infer_ctor`, `infer_pat`): each use of a
  constructor instantiates the ADT's type parameters with fresh variables, so
  `Some` behaves as `∀a. a -> a option`.

## The value restriction

`is_value` marks variables, literals, lambdas, tuples/lists/constructors of
values. Only values are generalized. For the pure core this rarely changes what
type-checks, but it is precisely the gate that keeps inference sound once mutable
references exist (v1.0): `let r = ref [] in …` is *not* a value, so `r` stays
monomorphic and the unsound "polymorphic reference" is rejected.

## Worked examples (with levels)

These are the `infer-adversarial` test cases; each is checked to infer exactly
the type shown (or to be rejected with the named error).

| Program | Result | Why |
|---------|--------|-----|
| `let id = fun x -> x in (id 1, id true)` | `int * bool` | `id`'s var is born at level 2 inside the let; after `leave_level` (back to 1) it is `> 1`, so it generalizes to `∀a. a -> a`; the two uses instantiate independently. |
| `fun f -> (f 1, f true)` | **type error** | `f` is a *lambda* parameter → monomorphic; `int` vs `bool` clash. |
| `fun x -> x x` | **occurs check** | unifying `'a` with `'a -> 'b`. |
| `fun x -> let y = x in (y, y)` | `'a -> 'a * 'a` (not `'a -> 'b * 'c`) | `x`'s var is born at level 1; inside the inner let, after `leave_level` the current level is 1, and the var's level (1) is **not** `> 1`, so `y` is **not** generalized — it stays the same variable as `x`. This is the level test in one line. |
| `let rec f = fun x -> (f 1, f true) in f` | **type error** | recursive `f` is monomorphic during its own definition. |
| `let xs = [] in (1 :: xs, true :: xs)` | `int list * bool list` | `[]` is a value → `xs : ∀a. a list`, used at two element types. |

## Files

- `lib/types.ml` — `typ` / `tvar` / `scheme`, `repr`, `new_var`, the `denv` of ADTs.
- `lib/infer.ml` — `unify` / `occurs_adjust`, `generalize` / `instantiate`,
  `is_value`, and the `infer` / `infer_bindings` rules.
- `test/test_infer.ml` — principal-type and adversarial cases.
