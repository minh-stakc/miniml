(* menhir grammar for MiniML.

   Top-level structure mirrors OCaml: a program is a sequence of [type] and
   [let] declarations (a bare expression at top level must be written
   [let _ = e]). A separate [expr_main] start symbol parses a single expression
   (used by the REPL and tests).

   Surface sugar desugared here:
   - [fun x y -> e]  -> nested single-argument lambdas
   - [\[a; b; c\]]   -> ECons (a, ECons (b, ECons (c, ENil)))
   - [C e] where C is a (nullary) constructor -> a saturated ECtor

   The expression grammar is layered for application (which has no operator
   token and must bind tighter than every binary operator), with precedence
   declarations for the infix/prefix operators. The [if]/[let]/[fun]/[match]
   forms sit at the [expr] level (not inside [op_expr]); like OCaml, they must
   be parenthesized to appear as an operand of a binary operator. *)

%{
open Ast

let mkspan (s, e) = Span.of_lexing s e

let rec mk_fun params body loc =
  match params with
  | [] -> body
  | p :: ps -> EFun (p, mk_fun ps body loc, mkspan loc)

let rec mk_list elems loc =
  match elems with
  | [] -> ENil (mkspan loc)
  | e :: es -> ECons (e, mk_list es loc, mkspan loc)

let rec mk_pat_list elems loc =
  match elems with
  | [] -> PNil (mkspan loc)
  | p :: ps -> PCons (p, mk_pat_list ps loc, mkspan loc)

(* A bare constructor parses as [ECtor (c, None)]; applying it saturates it. *)
let mk_app f x loc =
  match f with
  | ECtor (c, None, cs) -> ECtor (c, Some x, Span.merge cs (mkspan loc))
  | _ -> EApp (f, x, mkspan loc)
%}

%token <int> INT
%token <string> IDENT     (* lowercase: variables, type names *)
%token <string> UIDENT    (* Uppercase: constructors *)
%token <string> TYVAR     (* 'a *)
%token LET REC AND IN FUN IF THEN ELSE MATCH WITH TYPE OF TRUE FALSE NOT
%token ARROW COLONCOLON LPAREN RPAREN LBRACKET RBRACKET COMMA SEMI PIPE
%token UNDERSCORE EQUAL
%token PLUS MINUS STAR SLASH LT LE GT GE NEQ ANDAND OROR
%token REF BANG COLONEQ
%token LBRACE RBRACE DOT
%token EOF

(* Precedence ladder, lowest to highest. [no_pipe] is a pseudo-token used to
   make a match's case list extend rightward (the bar binds to the innermost
   match). *)
%nonassoc no_pipe
%left PIPE
%right COLONEQ
%right OROR
%right ANDAND
%nonassoc EQUAL NEQ LT LE GT GE
%right COLONCOLON
%left PLUS MINUS
%left STAR SLASH
%nonassoc UMINUS NOT

%start <Ast.program> program
%start <Ast.expr> expr_main

%%

(* ------------------------------------------------------------------ *)
program:
  | items = list(top_item) EOF { items }

expr_main:
  | e = seq_expr EOF { e }

(* Sequencing is allowed at top level and inside parentheses (kept out of bare
   let/fun bodies so the list separator `;` stays unambiguous — write
   `let r = ref 0 in (r := 1; !r)`). *)
seq_expr:
  | e = expr { e }
  | e1 = expr SEMI e2 = seq_expr { ESeq (e1, e2, mkspan $loc) }

top_item:
  | t = type_decl
      { IType t }
  | LET r = boption(REC) bs = separated_nonempty_list(AND, binding)
      { ILet (r, bs, mkspan $loc) }

bind_name:
  | x = IDENT { x }
  | UNDERSCORE { "_" } (* allow `let _ = e` *)

binding:
  | name = bind_name params = list(IDENT) EQUAL body = expr
      { { name; params; body; bspan = mkspan $loc } }

(* ------------------------------------------------------------------ *)
(* Type declarations: type 'a option = None | Some of 'a *)

type_decl:
  | TYPE params = type_params name = IDENT EQUAL option(PIPE)
      ctors = separated_nonempty_list(PIPE, ctor_decl)
      { { tname = name; tparams = params; tctors = ctors; tdspan = mkspan $loc } }

type_params:
  | (* empty *) { [] }
  | a = TYVAR { [ a ] }
  | LPAREN ps = separated_nonempty_list(COMMA, TYVAR) RPAREN { ps }

ctor_decl:
  | c = UIDENT { (c, None) }
  | c = UIDENT OF t = type_expr { (c, Some t) }

type_expr:
  | t = type_arrow { t }

type_arrow:
  | a = type_tuple ARROW b = type_arrow { TyArrow (a, b) }
  | t = type_tuple { t }

type_tuple:
  | ts = separated_nonempty_list(STAR, type_app)
      { match ts with [ t ] -> t | _ -> TyTuple ts }

type_app:
  | t = type_atom { t }
  | t = type_app name = IDENT { TyCon (name, [ t ]) }

type_atom:
  | a = TYVAR { TyVar a }
  | name = IDENT { TyCon (name, []) }
  | LPAREN t = type_expr RPAREN { t }
  | LPAREN t = type_expr COMMA ts = separated_nonempty_list(COMMA, type_expr) RPAREN name = IDENT
      { TyCon (name, t :: ts) }

(* ------------------------------------------------------------------ *)
(* Expressions *)

expr:
  | e = op_expr { e }
  | LET r = boption(REC) bs = separated_nonempty_list(AND, binding) IN body = expr
      { ELet (r, bs, body, mkspan $loc) }
  | FUN ps = nonempty_list(IDENT) ARROW body = expr
      { mk_fun ps body $loc }
  | IF c = expr THEN t = expr ELSE e = expr
      { EIf (c, t, e, mkspan $loc) }
  | MATCH scrut = expr WITH cs = cases
      { EMatch (scrut, cs, mkspan $loc) }

(* operator expressions and application, by precedence *)
op_expr:
  | e = app_expr { e }
  | e1 = op_expr PLUS e2 = op_expr { EBinop (Add, e1, e2, mkspan $loc) }
  | e1 = op_expr MINUS e2 = op_expr { EBinop (Sub, e1, e2, mkspan $loc) }
  | e1 = op_expr STAR e2 = op_expr { EBinop (Mul, e1, e2, mkspan $loc) }
  | e1 = op_expr SLASH e2 = op_expr { EBinop (Div, e1, e2, mkspan $loc) }
  | e1 = op_expr LT e2 = op_expr { EBinop (Lt, e1, e2, mkspan $loc) }
  | e1 = op_expr LE e2 = op_expr { EBinop (Le, e1, e2, mkspan $loc) }
  | e1 = op_expr GT e2 = op_expr { EBinop (Gt, e1, e2, mkspan $loc) }
  | e1 = op_expr GE e2 = op_expr { EBinop (Ge, e1, e2, mkspan $loc) }
  | e1 = op_expr EQUAL e2 = op_expr { EBinop (Eq, e1, e2, mkspan $loc) }
  | e1 = op_expr NEQ e2 = op_expr { EBinop (Neq, e1, e2, mkspan $loc) }
  | e1 = op_expr ANDAND e2 = op_expr { EBinop (And, e1, e2, mkspan $loc) }
  | e1 = op_expr OROR e2 = op_expr { EBinop (Or, e1, e2, mkspan $loc) }
  | e1 = op_expr COLONCOLON e2 = op_expr { ECons (e1, e2, mkspan $loc) }
  | e1 = op_expr COLONEQ e2 = op_expr { EAssign (e1, e2, mkspan $loc) }
  | MINUS e = op_expr %prec UMINUS { EUnop (Neg, e, mkspan $loc) }
  | NOT e = op_expr { EUnop (Not, e, mkspan $loc) }

app_expr:
  | e = simple_expr { e }
  | f = app_expr x = simple_expr { mk_app f x $loc }

(* A [simple_expr] is an atom followed by zero or more [.field] accesses.
   Threading field access through a suffix list (rather than a left-recursive
   [simple_expr DOT IDENT]) keeps it conflict-free with juxtaposition
   application: [f r.x] is [f (r.x)], with no shift/reduce ambiguity. *)
simple_expr:
  | a = atom fs = list(field_suffix)
      { List.fold_left (fun e l -> EField (e, l, mkspan $loc)) a fs }

field_suffix:
  | DOT l = IDENT { l }

atom:
  | i = INT { ELit (LInt i, mkspan $loc) }
  | TRUE { ELit (LBool true, mkspan $loc) }
  | FALSE { ELit (LBool false, mkspan $loc) }
  | x = IDENT { EVar (x, mkspan $loc) }
  | c = UIDENT { ECtor (c, None, mkspan $loc) }
  | BANG e = atom { EDeref (e, mkspan $loc) } (* binds tighter than [.], so !r.x = (!r).x *)
  | REF e = atom { ERef (e, mkspan $loc) }
  | LPAREN RPAREN { ELit (LUnit, mkspan $loc) }
  | LPAREN e = expr RPAREN { e }
  | LPAREN e = expr COMMA es = separated_nonempty_list(COMMA, expr) RPAREN
      { ETuple (e :: es, mkspan $loc) }
  | LPAREN e = expr SEMI s = seq_expr RPAREN { ESeq (e, s, mkspan $loc) }
  | LBRACKET RBRACKET { ENil (mkspan $loc) }
  | LBRACKET es = separated_nonempty_list(SEMI, expr) RBRACKET { mk_list es $loc }
  | LBRACE RBRACE { ERecord ([], mkspan $loc) }
  | LBRACE fs = separated_nonempty_list(SEMI, record_field) RBRACE { ERecord (fs, mkspan $loc) }

(* a single [label = value] in a record literal *)
record_field:
  | l = IDENT EQUAL e = expr { (l, e) }

(* ------------------------------------------------------------------ *)
(* match cases. The case list is right-recursive; [%prec no_pipe] on the
   single-case rule, with PIPE at higher precedence, makes a trailing bar bind
   to the innermost open match. *)

cases:
  | option(PIPE) cs = case_list { cs }

case_list:
  | c = case %prec no_pipe { [ c ] }
  | c = case PIPE cs = case_list { c :: cs }

case:
  | p = pattern ARROW e = expr { { lhs = p; rhs = e } }

(* ------------------------------------------------------------------ *)
(* Patterns *)

pattern:
  | p = cons_pattern { p }

cons_pattern:
  | l = app_pattern COLONCOLON r = cons_pattern { PCons (l, r, mkspan $loc) }
  | p = app_pattern { p }

app_pattern:
  | c = UIDENT p = atom_pattern { PCtor (c, Some p, mkspan $loc) }
  | p = atom_pattern { p }

atom_pattern:
  | UNDERSCORE { PWild (mkspan $loc) }
  | x = IDENT { PVar (x, mkspan $loc) }
  | i = INT { PLit (LInt i, mkspan $loc) }
  | MINUS i = INT { PLit (LInt (-i), mkspan $loc) } (* negative integer pattern *)
  | TRUE { PLit (LBool true, mkspan $loc) }
  | FALSE { PLit (LBool false, mkspan $loc) }
  | c = UIDENT { PCtor (c, None, mkspan $loc) }
  | LPAREN RPAREN { PLit (LUnit, mkspan $loc) }
  | LPAREN p = pattern RPAREN { p }
  | LPAREN p = pattern COMMA ps = separated_nonempty_list(COMMA, pattern) RPAREN
      { PTuple (p :: ps, mkspan $loc) }
  | LBRACKET RBRACKET { PNil (mkspan $loc) }
  | LBRACKET ps = separated_nonempty_list(SEMI, pattern) RBRACKET { mk_pat_list ps $loc }
