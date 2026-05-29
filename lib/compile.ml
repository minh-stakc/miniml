(** Compile the AST to bytecode for the stack VM.

    Key decisions (see [docs/05-bytecode-vm.md]):
    - {b de Bruijn} indices: a compile-time environment ([cenv], a name list)
      resolves each variable to an [ACCESS] index; the runtime environment mirrors
      it exactly, so no name lookup happens at run time.
    - {b closures} capture the whole environment ([CLOSURE]); a lambda body is
      compiled under [param :: cenv] and, when applied, runs with
      [arg :: captured_env] — which matches.
    - {b let rec} uses [CLOSUREREC] to build mutually-recursive closures over one
      shared, self-referential environment (the knot is tied by mutating each
      closure's captured env).
    - {b tail calls}: a [~tail] flag is threaded through; an application in tail
      position compiles to [TAILAPPLY] (no return frame), so tail recursion runs
      in constant frame-stack space.
    - {b pattern matching} compiles to a decision sequence: for each clause, first
      a sequence of shape [TEST]s (reading sub-values by [FIELD] paths from the
      scrutinee, jumping to the next clause on mismatch), then — only once the
      whole pattern matches — the variable bindings and the clause body. Splitting
      testing from binding keeps failure handling trivial (a failed test has
      changed nothing). An optimal decision-tree compiler is future work. *)

open Ast
open Bytecode

let label_counter = ref 0

let fresh_label () =
  incr label_counter;
  !label_counter
;;

(* compile-time environment: names, innermost first; ACCESS index = position. *)
type cenv = string list

let index (cenv : cenv) (x : string) : int =
  let rec go i = function
    | [] -> failwith ("compile: unbound variable " ^ x) (* impossible post-typecheck *)
    | y :: r -> if String.equal y x then i else go (i + 1) r
  in
  go 0 cenv
;;

let rec lambdas (params : string list) (body : expr) : expr =
  match params with
  | [] -> body
  | p :: ps -> EFun (p, lambdas ps body, span_of_expr body)
;;

(* For a pattern matched against the value reachable by [path] from the
   scrutinee: the shape tests to run (outer-first) and the variables to bind
   (each with its access path), collected left-to-right. *)
let rec collect (p : pat) (path : int list)
  : (int list * test) list * (string * int list) list
  =
  match p with
  | PWild _ -> [], []
  | PVar (x, _) -> [], [ x, path ]
  | PLit (LInt n, _) -> [ path, TInt n ], []
  | PLit (LBool b, _) -> [ path, TBool b ], []
  | PLit (LUnit, _) -> [], []
  | PNil _ -> [ path, TNil ], []
  | PCons (h, t, _) ->
    let th, bh = collect h (path @ [ 0 ]) in
    let tt, bt = collect t (path @ [ 1 ]) in
    (path, TCons) :: (th @ tt), bh @ bt
  | PTuple (ps, _) ->
    let parts = List.mapi (fun i p -> collect p (path @ [ i ])) ps in
    List.concat_map fst parts, List.concat_map snd parts
  | PCtor (c, None, _) -> [ path, TTag c ], []
  | PCtor (c, Some sub, _) ->
    let ts, bs = collect sub (path @ [ 0 ]) in
    (path, TTag c) :: ts, bs
;;

(* Push the value reachable by [path] from the scrutinee, which is at env index 0
   during a match's test and bind phases. *)
let push_path (path : int list) : instr list =
  ACCESS 0 :: List.map (fun i -> FIELD i) path
;;

let rec compile (cenv : cenv) ~(tail : bool) (e : expr) : instr list =
  match e with
  | EApp (f, a, _) ->
    compile cenv ~tail:false f
    @ compile cenv ~tail:false a
    @ [ (if tail then TAILAPPLY else APPLY) ]
  | EIf (c, t, e, _) ->
    let l_else = fresh_label () in
    if tail
    then
      compile cenv ~tail:false c
      @ [ JUMPIFNOT l_else ]
      @ compile cenv ~tail:true t
      @ [ LABEL l_else ]
      @ compile cenv ~tail:true e
    else (
      let l_end = fresh_label () in
      compile cenv ~tail:false c
      @ [ JUMPIFNOT l_else ]
      @ compile cenv ~tail:false t
      @ [ JUMP l_end; LABEL l_else ]
      @ compile cenv ~tail:false e
      @ [ LABEL l_end ])
  | ELet (false, bs, body, _) -> compile_let_nonrec cenv ~tail bs body
  | ELet (true, bs, body, _) -> compile_let_rec cenv ~tail bs body
  | EMatch (scrut, cases, _) -> compile_match cenv ~tail scrut cases
  | _ -> ret ~tail (compile_value cenv e)

and ret ~tail (code : instr list) : instr list = if tail then code @ [ RETURN ] else code

(* Value-producing leaf expressions: leave one value on the stack. Sub-expressions
   are compiled with the general [compile] (they may be control forms). *)
and compile_value (cenv : cenv) (e : expr) : instr list =
  let cv e = compile cenv ~tail:false e in
  match e with
  | ELit (LInt n, _) -> [ CONST n ]
  | ELit (LBool b, _) -> [ BOOL b ]
  | ELit (LUnit, _) -> [ UNIT ]
  | EVar (x, _) -> [ ACCESS (index cenv x) ]
  | EFun (x, body, _) ->
    let l_body = fresh_label () in
    let l_after = fresh_label () in
    [ CLOSURE l_body; JUMP l_after; LABEL l_body ]
    @ compile (x :: cenv) ~tail:true body
    @ [ LABEL l_after ]
  | ETuple (es, _) -> List.concat_map cv es @ [ MKTUPLE (List.length es) ]
  | ENil _ -> [ NIL ]
  | ECons (h, t, _) -> cv h @ cv t @ [ CONS ]
  | ECtor (c, None, _) -> [ MKDATA (c, false) ]
  | ECtor (c, Some a, _) -> cv a @ [ MKDATA (c, true) ]
  | EBinop (op, a, b, _) -> cv a @ cv b @ [ PRIM op ]
  | EUnop (Neg, a, _) -> cv a @ [ NEG ]
  | EUnop (Not, a, _) -> cv a @ [ NOT ]
  | ESeq (a, b, _) -> cv a @ [ POP ] @ cv b
  | (EApp _ | EIf _ | ELet _ | EMatch _) as e -> compile cenv ~tail:false e

and compile_let_nonrec (cenv : cenv) ~tail (bs : binding list) (body : expr) : instr list =
  let n = List.length bs in
  let rhs_code =
    List.concat_map
      (fun (b : binding) -> compile cenv ~tail:false (lambdas b.params b.body))
      bs
  in
  let cenv' = List.map (fun (b : binding) -> b.name) bs @ cenv in
  rhs_code
  @ List.init n (fun _ -> LET)
  @ compile cenv' ~tail body
  @ if tail then [] else [ ENDLET n ]

and compile_let_rec (cenv : cenv) ~tail (bs : binding list) (body : expr) : instr list =
  let n = List.length bs in
  let cenv_rec = List.map (fun (b : binding) -> b.name) bs @ cenv in
  let labels = List.map (fun _ -> fresh_label ()) bs in
  let l_after = fresh_label () in
  let body_blocks =
    List.concat
      (List.map2
         (fun (b : binding) lbl ->
            match lambdas b.params b.body with
            | EFun (p, fbody, _) -> LABEL lbl :: compile (p :: cenv_rec) ~tail:true fbody
            | _ -> failwith "compile: recursive binding is not a function")
         bs
         labels)
  in
  [ CLOSUREREC labels; JUMP l_after ]
  @ body_blocks
  @ [ LABEL l_after ]
  @ compile cenv_rec ~tail body
  @ if tail then [] else [ ENDLET n ]

and compile_match (cenv : cenv) ~tail (scrut : expr) (cases : case list) : instr list =
  let l_end = fresh_label () in
  let l_fail = fresh_label () in
  let cenv_m = "$scrut" :: cenv in
  let case_labels = List.map (fun _ -> fresh_label ()) cases in
  let next_labels = List.tl case_labels @ [ l_fail ] in
  let case_code (c : case) (l_here : int) (l_next : int) : instr list =
    let tests, binds = collect c.lhs [] in
    let test_code =
      List.concat_map (fun (path, t) -> push_path path @ [ TEST (t, l_next) ]) tests
    in
    let bind_pushes = List.concat_map (fun (_, path) -> push_path path) binds in
    let k = List.length binds in
    let cenv_body = List.map fst binds @ cenv_m in
    (LABEL l_here :: test_code)
    @ bind_pushes
    @ List.init k (fun _ -> LET)
    @ compile cenv_body ~tail c.rhs
    @ if tail then [] else [ ENDLET k; JUMP l_end ]
  in
  let cases_code =
    List.concat
      (List.map2
         (fun c (lh, ln) -> case_code c lh ln)
         cases
         (List.combine case_labels next_labels))
  in
  compile cenv ~tail:false scrut
  @ [ LET ]
  @ cases_code
  @ [ LABEL l_fail; MATCHFAIL; LABEL l_end ]
  @ if tail then [] else [ ENDLET 1 ]
;;

(* ------------------------------------------------------------------ *)
(* Two-pass assembler: resolve label ids to addresses, drop LABELs. *)

let assemble (instrs : instr list) : code =
  let tbl : (int, int) Hashtbl.t = Hashtbl.create 256 in
  let addr = ref 0 in
  List.iter
    (fun i ->
       match i with
       | LABEL l -> Hashtbl.replace tbl l !addr
       | _ -> incr addr)
    instrs;
  let resolve l =
    match Hashtbl.find_opt tbl l with
    | Some a -> a
    | None -> failwith "assemble: unresolved label"
  in
  let resolved =
    List.filter_map
      (fun i ->
         match i with
         | LABEL _ -> None
         | JUMP l -> Some (JUMP (resolve l))
         | JUMPIFNOT l -> Some (JUMPIFNOT (resolve l))
         | CLOSURE l -> Some (CLOSURE (resolve l))
         | CLOSUREREC ls -> Some (CLOSUREREC (List.map resolve ls))
         | TEST (t, l) -> Some (TEST (t, resolve l))
         | other -> Some other)
      instrs
  in
  Array.of_list resolved
;;

(* Compile a single closed expression to runnable bytecode. *)
let compile_expr (e : expr) : code =
  label_counter := 0;
  assemble (compile [] ~tail:false e @ [ STOP ])
;;
