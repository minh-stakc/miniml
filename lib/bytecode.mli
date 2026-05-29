(** The stack-VM instruction set.

    The VM ({!Vm}) is an environment machine: a register holds the current
    environment (a [Value.t list]); variables are resolved to de Bruijn indices at
    compile time and read with [ACCESS]. Closures capture the environment;
    application saves a return frame ([APPLY]) or reuses the current one in tail
    position ([TAILAPPLY]), giving proper tail calls.

    Jumps and closure entry points use integer {e labels} during compilation; the
    assembler ({!Compile.compile_expr}) resolves labels to addresses and drops the
    [LABEL] markers. See [docs/05-bytecode-vm.md]. *)

(** A shape test, used to compile pattern matching. *)
type test =
  | TInt of int
  | TBool of bool
  | TNil
  | TCons
  | TTag of string (** a data constructor, by name *)

type instr =
  | CONST of int (** push an integer *)
  | BOOL of bool
  | UNIT
  | ACCESS of int (** push the environment entry at this de Bruijn index *)
  | CLOSURE of int (** push a closure capturing the current env; arg = code label *)
  | CLOSUREREC of int list (** build n mutually-recursive closures, extend the env *)
  | LET (** pop a value and push it onto the environment *)
  | ENDLET of int (** drop n entries from the environment *)
  | APPLY (** non-tail call: push a return frame *)
  | TAILAPPLY (** tail call: reuse the current frame *)
  | RETURN (** pop a return frame; the result stays on the stack *)
  | MKTUPLE of int (** pop n values, push a tuple *)
  | NIL (** push the empty list *)
  | CONS (** pop tail then head, push [head :: tail] *)
  | MKDATA of string * bool (** build a constructor value; bool = has an argument *)
  | FIELD of int (** push the i-th sub-component of the value on top *)
  | TEST of test * int (** pop a value; if it fails the test, jump to the label *)
  | PRIM of Ast.binop (** binary primitive (pops 2) *)
  | NEG (** unary integer negation *)
  | NOT (** boolean negation *)
  | JUMP of int
  | JUMPIFNOT of int (** pop a bool; jump if false *)
  | POP (** discard the top of the stack *)
  | MKREF (** pop a value, push a fresh reference cell holding it *)
  | DEREF (** pop a reference, push its contents *)
  | ASSIGN (** pop a value then a reference, store the value, push unit *)
  | MKRECORD of string list (** pop one value per label, push a record *)
  | GETFIELD of string (** pop a record, push the named field's value *)
  | MATCHFAIL (** runtime match failure (unreachable for exhaustive matches) *)
  | LABEL of int (** pseudo-instruction: a jump target, removed by the assembler *)
  | STOP (** halt; the result is the top of the stack *)

type code = instr array
