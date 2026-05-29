(** The stack VM: executes the bytecode produced by [Compile].

    The loop is {e iterative} (a [while] over a mutable program counter), so a
    deeply-recursive MiniML program never overflows OCaml's own call stack — its
    activation records live on the VM's [frames] list instead. With proper tail
    calls ([TAILAPPLY] does not push a frame) a tail-recursive loop keeps that
    list at constant depth ([max_frame_depth] proves it in the tests).

    Registers: [pc], an operand [stack], the current [env] (a [Value.t list]), and
    a [frames] return stack. [Type_trap] marks a stuck state that a well-typed
    program can never reach; the soundness property (v0.6) asserts it never fires
    on type-checked input. See [docs/05-bytecode-vm.md]. *)

open Bytecode
open Value

exception Type_trap of string

type frame =
  { ret_pc : int
  ; ret_env : Value.t list
  }

(* Maximum return-frame depth reached during the most recent [run] — used by the
   tests to demonstrate that tail calls run in constant space. *)
let max_frame_depth = ref 0

let run (code : code) : Value.t =
  let stack = ref ([] : Value.t list) in
  let env = ref ([] : Value.t list) in
  let frames = ref ([] : frame list) in
  let depth = ref 0 in
  max_frame_depth := 0;
  let pc = ref 0 in
  let result = ref VUnit in
  let running = ref true in
  let push v = stack := v :: !stack in
  let pop () =
    match !stack with
    | v :: r ->
      stack := r;
      v
    | [] -> raise (Type_trap "operand stack underflow")
  in
  let rec drop n l =
    if n <= 0
    then l
    else (
      match l with
      | _ :: r -> drop (n - 1) r
      | [] -> [])
  in
  let field i (v : Value.t) : Value.t =
    match v with
    | VData (_, Some a) when i = 0 -> a
    | VTuple vs ->
      (try List.nth vs i with
       | _ -> raise (Type_trap "tuple field index"))
    | VList (h :: t) ->
      if i = 0 then h else if i = 1 then VList t else raise (Type_trap "list field index")
    | _ -> raise (Type_trap "field of a non-aggregate value")
  in
  let does_match (t : test) (v : Value.t) : bool =
    match t, v with
    | TInt n, VInt m -> n = m
    | TBool b, VBool c -> Bool.equal b c
    | TNil, VList l -> l = []
    | TCons, VList l -> l <> []
    | TTag c, VData (c', _) -> String.equal c c'
    | _ -> raise (Type_trap "ill-typed pattern test")
  in
  while !running do
    let i = code.(!pc) in
    incr pc;
    match i with
    | CONST n -> push (VInt n)
    | BOOL b -> push (VBool b)
    | UNIT -> push VUnit
    | ACCESS i ->
      (match List.nth_opt !env i with
       | Some v -> push v
       | None -> raise (Type_trap "environment access out of range"))
    | CLOSURE c -> push (VClosVM { code = c; venv = !env })
    | CLOSUREREC labels ->
      let closures = List.map (fun c -> { code = c; venv = [] }) labels in
      let rec_env = List.map (fun c -> VClosVM c) closures @ !env in
      List.iter (fun c -> c.venv <- rec_env) closures;
      env := rec_env
    | LET ->
      let v = pop () in
      env := v :: !env
    | ENDLET n -> env := drop n !env
    | APPLY ->
      let arg = pop () in
      let clos = pop () in
      (match clos with
       | VClosVM c ->
         frames := { ret_pc = !pc; ret_env = !env } :: !frames;
         incr depth;
         if !depth > !max_frame_depth then max_frame_depth := !depth;
         env := arg :: c.venv;
         pc := c.code
       | _ -> raise (Type_trap "application of a non-function"))
    | TAILAPPLY ->
      let arg = pop () in
      let clos = pop () in
      (match clos with
       | VClosVM c ->
         env := arg :: c.venv;
         pc := c.code
       | _ -> raise (Type_trap "application of a non-function"))
    | RETURN ->
      (match !frames with
       | f :: r ->
         frames := r;
         decr depth;
         pc := f.ret_pc;
         env := f.ret_env
       | [] ->
         running := false;
         result
         := (match !stack with
              | v :: _ -> v
              | [] -> VUnit))
    | MKTUPLE n ->
      let rec take n acc = if n = 0 then acc else take (n - 1) (pop () :: acc) in
      push (VTuple (take n []))
    | NIL -> push (VList [])
    | CONS ->
      let t = pop () in
      let h = pop () in
      (match t with
       | VList l -> push (VList (h :: l))
       | _ -> raise (Type_trap "tail of :: is not a list"))
    | MKDATA (name, false) -> push (VData (name, None))
    | MKDATA (name, true) ->
      let a = pop () in
      push (VData (name, Some a))
    | FIELD i ->
      let v = pop () in
      push (field i v)
    | TEST (t, lbl) ->
      let v = pop () in
      if does_match t v then () else pc := lbl
    | PRIM op ->
      let b = pop () in
      let a = pop () in
      push (Eval.eval_binop op a b)
    | NEG ->
      (match pop () with
       | VInt n -> push (VInt (-n))
       | _ -> raise (Type_trap "negation of a non-integer"))
    | NOT ->
      (match pop () with
       | VBool b -> push (VBool (not b))
       | _ -> raise (Type_trap "not of a non-boolean"))
    | JUMP l -> pc := l
    | JUMPIFNOT l ->
      (match pop () with
       | VBool false -> pc := l
       | VBool true -> ()
       | _ -> raise (Type_trap "if condition is not a boolean"))
    | POP -> ignore (pop ())
    | MKREF ->
      let v = pop () in
      push (VRef (ref v))
    | DEREF ->
      (match pop () with
       | VRef cell -> push !cell
       | _ -> raise (Type_trap "dereference of a non-reference"))
    | ASSIGN ->
      let v = pop () in
      (match pop () with
       | VRef cell ->
         cell := v;
         push VUnit
       | _ -> raise (Type_trap "assignment to a non-reference"))
    | MATCHFAIL -> raise (Type_trap "match failure (non-exhaustive)")
    | LABEL _ -> () (* removed by the assembler; defensive no-op *)
    | STOP ->
      running := false;
      result := pop ()
  done;
  !result
;;

(* Compile and run a closed expression. *)
let run_expr (e : Ast.expr) : Value.t = run (Compile.compile_expr e)
