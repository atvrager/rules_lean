import Scheme.Env

/-!
The primitive procedures. They are values of the form `Value.primitive name`,
and `call` dispatches on that name. `display` and `newline` write to standard
output, which is why the evaluator, and not just this module, runs in `IO`.
Arithmetic is integer arithmetic; `/` truncates toward zero and `modulo` follows
the sign of its second argument.
-/

open Scheme

namespace Scheme.Prim

private def arity (name : String) (expected : String) : ExceptT String IO α :=
  throw s!"{name}: expected {expected}"

private def wantNumber (name : String) (v : Value) : ExceptT String IO Int :=
  match v with
  | .number n => pure n
  | _ => throw s!"{name}: expected a number, got {v.writeString}"

private def wantString (name : String) (v : Value) : ExceptT String IO String :=
  match v with
  | .string s => pure s
  | _ => throw s!"{name}: expected a string, got {v.writeString}"

private def wantPair (name : String) (v : Value) : ExceptT String IO (Value × Value) :=
  match v with
  | .pair c d => pure (c, d)
  | _ => throw s!"{name}: expected a pair, got {v.writeString}"

/-- Convert a proper list to a Lean list. -/
private def toList (name : String) : Value → ExceptT String IO (List Value)
  | .nil => pure []
  | .pair c d => do
    let rest ← toList name d
    pure (c :: rest)
  | v => throw s!"{name}: expected a list, got {v.writeString}"

/-- Fold a binary integer operation over the arguments. -/
private def foldNumbers (name : String) (init : Int) (f : Int → Int → Int)
    (args : List Value) : ExceptT String IO Value := do
  let ns ← args.mapM (wantNumber name)
  pure (.number (ns.foldl f init))

/-- Fold a binary integer operation over one or more arguments. -/
private def foldAtLeastOne (name : String) (f : Int → Int → Int)
    (args : List Value) : ExceptT String IO Value :=
  match args with
  | [] => arity name "at least 1 argument"
  | x :: rest => do
    let first ← wantNumber name x
    let ns ← rest.mapM (wantNumber name)
    pure (.number (ns.foldl f first))

/-- Fold an integer division, refusing a zero divisor. -/
private def divFold (name : String) (acc : Int) : List Int → Except String Int
  | [] => .ok acc
  | y :: rest =>
    if y == 0 then .error s!"{name}: division by zero"
    else divFold name (acc / y) rest

/-- Unary integer operation. -/
private def unaryNumber (name : String) (f : Int → Int)
    (args : List Value) : ExceptT String IO Value :=
  match args with
  | [x] => do
    let n ← wantNumber name x
    pure (.number (f n))
  | _ => arity name "1 argument"

/-- Check consecutive arguments against a binary relation. -/
private def compareChain (name : String) (f : Int → Int → Bool)
    (args : List Value) : ExceptT String IO Value := do
  let ns ← args.mapM (wantNumber name)
  let ok := (ns.zip ns.tail).all (fun (a, b) => f a b)
  pure (.boolean ok)

/-- Append proper lists; the last argument becomes the tail. -/
private def appendAll : List Value → ExceptT String IO Value
  | [] => pure .nil
  | [x] => pure x
  | x :: rest => do
    let vs ← toList "append" x
    let tail ← appendAll rest
    pure (vs.foldr (fun v acc => .pair v acc) tail)

/-- Apply a primitive procedure by name. -/
def call (name : String) (args : List Value) : ExceptT String IO Value :=
  match name with
  | "+" => foldNumbers name 0 (· + ·) args
  | "*" => foldNumbers name 1 (· * ·) args
  | "-" =>
    match args with
    | [] => arity name "at least 1 argument"
    | [x] => do
      let n ← wantNumber name x
      pure (.number (-n))
    | x :: rest => do
      let first ← wantNumber name x
      let ns ← rest.mapM (wantNumber name)
      pure (.number (ns.foldl (· - ·) first))
  | "/" =>
    match args with
    | [] => arity name "at least 1 argument"
    | [x] => do
      let n ← wantNumber name x
      if n == 0 then throw "/: division by zero" else pure (.number (1 / n))
    | x :: rest => do
      let first ← wantNumber name x
      let ns ← rest.mapM (wantNumber name)
      match divFold name first ns with
      | .ok n => pure (.number n)
      | .error e => throw e
  | "=" => compareChain name (· == ·) args
  | "<" => compareChain name (· < ·) args
  | ">" => compareChain name (· > ·) args
  | "<=" => compareChain name (· <= ·) args
  | ">=" => compareChain name (· >= ·) args
  | "abs" => unaryNumber name (fun n => if n < 0 then -n else n) args
  | "min" => foldAtLeastOne name (fun a b => if a <= b then a else b) args
  | "max" => foldAtLeastOne name (fun a b => if a <= b then b else a) args
  | "modulo" =>
    match args with
    | [a, b] => do
      let x ← wantNumber name a
      let y ← wantNumber name b
      if y == 0 then throw "modulo: division by zero" else pure (.number (x % y))
    | _ => arity name "2 arguments"
  | "not" =>
    match args with
    | [v] => pure (.boolean (!(v.truthy)))
    | _ => arity name "1 argument"
  | "cons" =>
    match args with
    | [a, b] => pure (.pair a b)
    | _ => arity name "2 arguments"
  | "car" =>
    match args with
    | [v] => do
      let (c, _) ← wantPair name v
      pure c
    | _ => arity name "1 argument"
  | "cdr" =>
    match args with
    | [v] => do
      let (_, d) ← wantPair name v
      pure d
    | _ => arity name "1 argument"
  | "list" => pure (args.foldr (fun v acc => .pair v acc) .nil)
  | "length" =>
    match args with
    | [v] => do
      let vs ← toList name v
      pure (.number (Int.ofNat vs.length))
    | _ => arity name "1 argument"
  | "null?" =>
    match args with
    | [v] => pure (.boolean (match v with | .nil => true | _ => false))
    | _ => arity name "1 argument"
  | "append" => appendAll args
  | "string-append" => do
    let ss ← args.mapM (wantString name)
    pure (.string (ss.foldl (· ++ ·) ""))
  | "display" =>
    match args with
    | [v] => do
      IO.print v.displayString
      pure .nil
    | _ => arity name "1 argument"
  | "newline" =>
    match args with
    | [] => do
      IO.print "\n"
      pure .nil
    | _ => arity name "no arguments"
  | _ => throw s!"unknown primitive: {name}"

/-- The names installed in the initial environment. -/
def names : List String := [
  "+", "-", "*", "/", "=", "<", ">", "<=", ">=",
  "abs", "min", "max", "modulo", "not",
  "cons", "car", "cdr", "list", "length", "null?", "append",
  "string-append", "display", "newline"
]

/-- The global environment: the boolean constants and every primitive. -/
def initialEnv : Env :=
  [("#t", Value.boolean true), ("#f", Value.boolean false)] ++
    names.map (fun n => (n, Value.primitive n))

end Scheme.Prim
