# 02 — Lexer & Parser

The front end is the standard OCaml toolchain: **ocamllex** for the lexer
(`lib/lexer.mll`) and **menhir** for the parser (`lib/parser.mly`). The grammar
has **zero shift/reduce and reduce/reduce conflicts** — getting there required
three deliberate design decisions, documented below.

## The lexer

`token : Lexing.lexbuf -> Parser.token` is a longest-match scanner. Points worth
knowing:

- **Keywords vs. identifiers.** Identifiers are scanned by one rule
  (`lower idchar*`) and then looked up in a keyword `Hashtbl`; a hit returns the
  keyword token (`LET`, `MATCH`, …), a miss returns `IDENT s`. This keeps the
  rule set small and unambiguous.
- **Case distinguishes variables from constructors.** `ident` (lowercase) →
  `IDENT`; `uident` (uppercase) → `UIDENT`. The parser uses that to tell
  `x` (a variable) from `Cons` (a constructor) purely lexically — exactly as
  OCaml does.
- **Type variables.** `'a` lexes to `TYVAR "a"` via the rule `"'" ident`.
- **Wildcard vs. identifier.** The `"_"` rule precedes the `ident` rule so a
  bare `_` becomes `UNDERSCORE`, while `_x` (longer match) stays an `IDENT`.
- **Nested comments.** `(* ... (* ... *) ... *)` is handled by a separate
  `comment` lexer rule carrying a depth counter; only depth 0 returns to
  scanning tokens. An EOF inside a comment is a lexing error.
- **Positions.** `Lexing.new_line` is called on every newline (in both the token
  and comment rules) so menhir's `$startpos`/`$endpos` — and therefore every
  AST node's `Span.t` — stay accurate across lines.

## The expression grammar is layered

Binary operators are handled with precedence declarations, but **function
application has no operator token** and must bind tighter than every operator.
Encoding that with precedence alone is awkward, so application gets its own
grammar layer:

```
simple_expr   atoms: literals, identifiers, (e), (e, …), [e; …]
app_expr      simple_expr | app_expr simple_expr        -- left-assoc application
op_expr       app_expr | op_expr OP op_expr | -e | not e -- infix/prefix operators
expr          op_expr | let…in | fun…-> | if…then…else | match…with
```

`if` / `let` / `fun` / `match` live at the `expr` level, **not** inside
`op_expr`. The consequence — identical to OCaml — is that they must be
parenthesized to appear as an operand: `1 + (if c then a else b)` is required;
`1 + if …` is a syntax error. This keeps the grammar unambiguous without giving
those forms artificial operator precedence.

### Precedence ladder (lowest → highest)

```
no_pipe   (pseudo-token; see "nested match" below)
PIPE
||                     right
&&                     right
=  <>  <  <=  >  >=     non-associative   (so a < b < c is rejected)
::                     right
+  -                   left
*  /                   left
unary -  /  not        (highest; via %prec UMINUS on the MINUS-prefix rule)
```

Application binds tighter than all of these by virtue of the layering above, not
by a precedence number.

### Desugaring in semantic actions

- `fun x y -> e` → `EFun (x, EFun (y, e))` (lambdas are curried).
- `[a; b; c]` → `ECons (a, ECons (b, ECons (c, ENil)))`.
- Constructor application: a bare constructor parses as `ECtor (c, None)`;
  `mk_app` rewrites `ECtor(c,None)` applied to an argument into the saturated
  `ECtor (c, Some arg)`, so `Some x` and `Node (l, v, r)` work while `f None`
  (a constructor passed as an argument) still parses correctly.

## How the grammar reaches zero conflicts

menhir initially reported 6 shift/reduce states and 1 reduce/reduce conflict.
Each traced to a real ambiguity, fixed at the source rather than papered over:

1. **Top-level juxtaposition (shift/reduce).** Allowing a bare expression as a
   top-level item made `e1 - e2` ambiguous with two items `e1` then `-e2`, and
   `f x  Foo` ambiguous with `f x` then `Foo`. Fix: top-level items are `type`
   and `let` declarations only — exactly like an OCaml `.ml` file, where a
   standalone expression must be written `let _ = e`. A separate `expr_main`
   start symbol (`expr EOF`) parses a single expression for the REPL and tests,
   with no juxtaposition to be ambiguous about.

2. **`;` overloaded (reduce/reduce).** `[a; b]` (semicolon as a list separator)
   collided with `e1; e2` (semicolon as sequencing). Sequencing only matters
   once side effects exist, so it is deferred to the mutable-references
   milestone (v1.0); for now `;` is unambiguously a list separator. (The `ESeq`
   AST node already exists, unused, awaiting that milestone.)

3. **Dangling match bar (shift/reduce).** In
   `match … with p -> match … with q -> a | r -> b`, the `| r` should attach to
   the inner match. The case list is right-recursive, and a `no_pipe`
   pseudo-token (declared just below `PIPE`) on the single-case rule makes the
   parser prefer shifting `PIPE` — i.e. attaching the bar to the innermost open
   match — so the conflict is resolved deterministically instead of
   "arbitrarily". (`if` needs no analogous trick: `else` is mandatory, so there
   is no dangling-`else`.)

The grammar is built with `--explain`; the generated `parser.conflicts` is empty.
