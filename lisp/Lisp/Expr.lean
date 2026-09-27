import VM.Word

open VM
namespace Lisp

/-- Core expressions of the Lisp. -/
inductive Expr where
  | lit (n : Int)
  | var (name : String)
  | op (kind : VM.Op) (left : Expr) (right : Expr)
  | lam (param : String) (body : Expr)
  | app (fn : Expr) (arg : Expr)
  | ite (cond : Expr) (then_ : Expr) (else_ : Expr)
  | letE (name : String) (value : Expr) (body : Expr)
deriving Repr, DecidableEq

namespace Expr

/-- The names an expression reads from its environment. -/
def freeVars : Expr → List String
  | .lit _ => []
  | .var x => [x]
  | .op _ a b => a.freeVars ++ b.freeVars
  | .lam x b => b.freeVars.erase x
  | .app f a => f.freeVars ++ a.freeVars
  | .ite c t e => c.freeVars ++ t.freeVars ++ e.freeVars
  | .letE x v b => v.freeVars ++ (b.freeVars.erase x)

end Expr

end Lisp
