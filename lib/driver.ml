(** Glue between the phases, for the REPL and the file runner.

    A {!state} accumulates type declarations, the type-checking environment, and
    the source of every top-level [let] entered so far. To {e run} an expression
    the driver wraps those accumulated [let]s around it to form a closed
    expression, then type-checks it and executes it on the {b bytecode VM} — so
    the interactive session exercises the real compiler + VM, not a shortcut.

    A phrase is parsed as an expression if it can be, otherwise as a sequence of
    declarations. Type errors are rendered with a caret ([Errors.format_at]);
    non-exhaustive/redundant matches are reported as warnings. *)

type state =
  { denv : Types.denv
  ; env : Env.t (* type schemes of top-level bindings *)
  ; decls : Ast.item list (* accumulated declarations, in order *)
  }

let initial () : state = { denv = Types.new_denv (); env = Env.empty; decls = [] }

(* Wrap the accumulated [let] declarations around [e] to make it closed. *)
let close (st : state) (e : Ast.expr) : Ast.expr =
  List.fold_right
    (fun (item : Ast.item) acc ->
       match item with
       | Ast.ILet (is_rec, bs, sp) -> Ast.ELet (is_rec, bs, acc, sp)
       | Ast.IType _ | Ast.IExpr _ -> acc)
    st.decls
    e
;;

let run_expr (st : state) (e : Ast.expr) : Value.t = Vm.run_expr (close st e)

(* Parse a phrase: try a single expression; if that fails, a declaration list. *)
let parse (input : string) : Ast.item list =
  match
    try Some (Parser.expr_main Lexer.token (Lexing.from_string input)) with
    | Parser.Error -> None
  with
  | Some e -> [ Ast.IExpr e ]
  | None -> Parser.program Lexer.token (Lexing.from_string input)
;;

let warning_lines ~(src : string) : string list =
  List.map
    (fun (w : Infer.warning) ->
       Errors.format_at ~src w.Infer.wspan ("Warning: " ^ w.Infer.wmsg))
    (Infer.get_warnings ())
;;

(* Process one already-parsed item; returns the new state and output lines. *)
let process (st : state) (item : Ast.item) : state * string list =
  match item with
  | Ast.IType td ->
    Types.register_type st.denv td;
    ( { st with decls = st.decls @ [ item ] }
    , [ Printf.sprintf "type %s defined" td.Ast.tname ] )
  | Ast.ILet (is_rec, bs, _) ->
    let env' = Infer.infer_decl st.denv st.env is_rec bs in
    let st' = { st with env = env'; decls = st.decls @ [ item ] } in
    let lines =
      List.map
        (fun (b : Ast.binding) ->
           let scheme =
             match Env.find b.Ast.name env' with
             | Some s -> s
             | None -> assert false
           in
           let v = run_expr st' (Ast.EVar (b.Ast.name, Span.dummy)) in
           Printf.sprintf
             "%s : %s = %s"
             b.Ast.name
             (Pretty.scheme scheme)
             (Value.to_string v))
        bs
    in
    st', lines
  | Ast.IExpr e ->
    let scheme = Infer.infer_scheme st.denv st.env e in
    let v = run_expr st e in
    st, [ Printf.sprintf "- : %s = %s" (Pretty.scheme scheme) (Value.to_string v) ]
;;

(* Feed a phrase of source; returns the new state and formatted output. *)
let feed (st : state) (input : string) : state * string =
  Infer.clear_warnings ();
  match parse input with
  | exception Lexer.Lexing_error msg -> st, "Lex error: " ^ msg
  | exception Parser.Error -> st, "Parse error"
  | items ->
    (match
       List.fold_left
         (fun (st, acc) item ->
            let st', lines = process st item in
            st', acc @ lines)
         (st, [])
         items
     with
     | st', lines -> st', String.concat "\n" (lines @ warning_lines ~src:input)
     | exception Infer.Type_error (sp, msg) -> st, Errors.format_at ~src:input sp msg
     | exception Infer.Occurs_check (sp, msg) -> st, Errors.format_at ~src:input sp msg)
;;
