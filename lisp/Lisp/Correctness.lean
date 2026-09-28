import Lisp.Expr
import Lisp.Eval
import Lisp.Compile
import VM.Machine
import Lisp.Env
import Lisp.Subst

namespace Lisp

open VM

/-- Compiler execution theorem for literals:
Executing `compile (.lit n)` places `VM.Value.lit n` onto the operand stack. -/
theorem run_lit (fuel : Nat) (s : VM.State) (n : Int) (hfuel : fuel ≥ 1) :
    run fuel s (compile (.lit n)) = some { s with stack := VM.Value.lit n :: s.stack } := by
  cases fuel with
  | zero => omega
  | succ f =>
    simp [compile, run]

/-- Evaluator agreement on literals. -/
theorem eval_lit (fuel : Nat) (env : Lisp.Env) (n : Int) (hfuel : fuel ≥ 1) :
    eval fuel env (.lit n) = some (.lit n) := by
  cases fuel with
  | zero => omega
  | succ f =>
    simp [eval]

/-- Evaluating `compile (.lit n)` on the machine yields the literal value on the stack. -/
theorem compile_correct_lit (fuel : Nat) (n : Int) (s : VM.State) (hfuel : fuel ≥ 1) :
    (run fuel s (compile (.lit n))).map (fun s' => s'.stack) =
    some (VM.Value.lit n :: s.stack) := by
  cases fuel with
  | zero => omega
  | succ f =>
    simp [compile, run]

/-- Compiler agreement for conditional execution (`ite`):
Running compiled `ite c t e` executes the condition and then selects the corresponding branch. -/
theorem compile_correct_ite (fuel : Nat) (c t e : Expr) (s : VM.State)
    (n : Int) (s1 s2 : VM.State)
    (hc : run fuel s (compile c) = some s1)
    (hpop : s1.popInt = some (n, s2)) :
    run (fuel + 1) s (compile (.ite c t e)) =
    run fuel s2 (if n == 0 then compile e else compile t) := by
  simp [compile, run, hc, hpop]

/-- Compiler agreement for local binding (`letE`):
Compiled let-expressions extend the machine environment register with the evaluated value. -/
theorem compile_correct_letE (fuel : Nat) (x : String) (v body : Expr) (s : VM.State)
    (s1 : VM.State) (val : VM.Value) (rest : List VM.Value)
    (hv : run fuel s (compile v) = some s1)
    (hstack : s1.stack = val :: rest) :
    run (fuel + 1) s (compile (.letE x v body)) =
    run fuel { s1 with stack := rest, env := (x, val) :: s1.env } (compile body) := by
  simp [compile, run, hv, hstack]

end Lisp
