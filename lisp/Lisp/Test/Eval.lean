import Lisp.Compile
import Lisp.Eval
import VM.Machine

open Lisp VM

/-!
Executable checks. `eval` and `run (compile e)` must agree on every sample.
The evaluator and the machine are independent definitions, so agreement is
evidence about both.
-/

/-- Run an expression through both paths and compare the results. -/
def agrees (name : String) (expr : Expr) : IO Bool := do
  let direct := eval 100 [] expr
  let through := (run 100 {} (compile expr)).bind (·.stack.head?)
  let same :=
    match direct, through with
    | some (.lit a), some (.lit b) => a == b
    | none, none => true
    | _, _ => false
  if same then
    IO.println s!"ok   {name}"
  else
    IO.println s!"FAIL {name}: eval = {repr direct}, run = {repr through}"
  return same

def samples : List (String × Expr) := [
  ("lit", .lit 7),
  ("add", .op .add (.lit 2) (.lit 3)),
  ("nested-op", .op .mul (.op .add (.lit 2) (.lit 3)) (.lit 4)),
  ("if-true", .ite (.lit 1) (.lit 10) (.lit 20)),
  ("if-false", .ite (.lit 0) (.lit 10) (.lit 20)),
  ("let", .letE "x" (.lit 5) (.op .add (.var "x") (.lit 1))),
  ("shadow", .letE "x" (.lit 1) (.letE "x" (.lit 2) (.var "x"))),
  ("closure", .app (.lam "x" (.op .add (.var "x") (.lit 1))) (.lit 41)),
  ("closure-captures-env",
    .letE "y" (.lit 100)
      (.app (.lam "x" (.op .add (.var "x") (.var "y"))) (.lit 1))),
  ("higher-order",
    .app (.app (.lam "f" (.app (.var "f") (.lit 3)))
      (.lam "z" (.op .mul (.var "z") (.var "z")))) (.lit 0)),
]

def main : IO Unit := do
  let results ← samples.mapM fun (name, expr) => agrees name expr
  if results.all id then
    IO.println s!"lisp machine: {results.length} checks pass"
  else
    IO.println "lisp machine: FAILURES"
    IO.Process.exit 1
