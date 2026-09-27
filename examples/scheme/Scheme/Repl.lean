import Scheme.Ast
import Scheme.Env
import Scheme.Eval
import Scheme.Lexer
import Scheme.Parser
import Scheme.Prim
import Scheme.Token

/-!
The command-line driver.

* `--eval "<expr>"` evaluates one expression, printing its value. The option may
  be repeated; definitions from earlier `--eval`s are visible to later ones. An
  error is reported as `error: <msg>` on standard error and exits with 1.
* `--file <path>` runs a file, printing the value of its last form.
* With no options, the driver reads standard input and evaluates each non-empty
  line, printing its value.

Errors from `--file` and from standard input are reported on standard error and
do not stop the run. The unspecified value (the empty list) is not printed.

Core Lean offers no `IO.getArgs`, so the arguments arrive through the `main`
parameter, which is the convention the toolchain supports for `lean --run`.
-/

open Scheme

namespace Scheme.Repl

/-- Fuel for one program. -/
def fuel : Nat := 1000000

/-- What the driver has been asked to do. -/
private inductive Action where
  | evalExpr (src : String)
  | runFile (path : String)

/-- Parse the command line. Arguments that are not options are ignored, so that
the driver works whether or not the runner hands it its own arguments. -/
def parseArgs : List String → List Action → Except String (List Action)
  | [], acc => .ok acc.reverse
  | "--eval" :: src :: rest, acc => parseArgs rest (.evalExpr src :: acc)
  | ["--eval"], _ => .error "--eval requires an expression"
  | "--file" :: path :: rest, acc => parseArgs rest (.runFile path :: acc)
  | ["--file"], _ => .error "--file requires a path"
  | _ :: rest, acc => parseArgs rest acc

/-- Evaluate a compiled program, returning the environment it extended together
with the value of its last form. -/
def runForms (env : Env) (prog : List Ast) : IO (Env × Except String Value) := do
  let r ← (Eval.evalSeq fuel env prog).run
  match r with
  | .ok (env', v) => pure (env', .ok v)
  | .error e => pure (env, .error e)

/-- Lex, read, compile and evaluate one source string. -/
def runSource (env : Env) (src : String) : IO (Env × Except String Value) := do
  match Lexer.lex src with
  | .error e => pure (env, .error e)
  | .ok toks =>
    match Parser.parse toks with
    | .error e => pure (env, .error e)
    | .ok sexps =>
      match Ast.compileProgram sexps with
      | .error e => pure (env, .error e)
      | .ok prog => runForms env prog

/-- Print a value, unless it is unspecified. -/
private def showValue (v : Value) : IO Unit :=
  match v with
  | .nil => pure ()
  | _ => IO.println v.writeString

/-- Run the requested actions in order. -/
def runActions : List Action → Env → IO UInt32
  | [], _ => pure 0
  | .evalExpr src :: rest, env => do
    let (env', r) ← runSource env src
    match r with
    | .ok v => showValue v; runActions rest env'
    | .error e => IO.eprintln s!"error: {e}"; pure 1
  | .runFile path :: rest, env => do
    let contents? ←
      try
        some <$> IO.FS.readFile path
      catch _ =>
        pure none
    match contents? with
    | none => IO.eprintln s!"error: cannot read {path}"; runActions rest env
    | some src => do
      let (env', r) ← runSource env src
      match r with
      | .ok v => showValue v; runActions rest env'
      | .error e => IO.eprintln s!"error: {e}"; runActions rest env

/-- Evaluate the non-empty lines of a session. -/
private def runLines : List String → Env → IO UInt32
  | [], _ => pure 0
  | line :: rest, env => do
    if line.trimAscii.isEmpty then
      runLines rest env
    else do
      let (env', r) ← runSource env line
      match r with
      | .ok v => showValue v; runLines rest env'
      | .error e => IO.eprintln s!"error: {e}"; runLines rest env'

/-- Read all of standard input and evaluate it line by line. -/
def runStdin (env : Env) : IO UInt32 := do
  let input ← (← IO.getStdin).readToEnd
  runLines (input.splitOn "\n") env

end Scheme.Repl

open Scheme.Repl

/-- Command-line entry point. -/
def main (args : List String) : IO UInt32 := do
  match parseArgs args [] with
  | .error e => IO.eprintln s!"error: {e}"; pure 1
  | .ok [] => runStdin Prim.initialEnv
  | .ok actions => runActions actions Prim.initialEnv
