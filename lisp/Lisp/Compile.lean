import Lisp.Expr

open VM
namespace Lisp

/-- Compile core expressions to machine code.

The compiler carries no environment: `clos` captures the environment register
at run time, and `letE` extends it.
-/
def compile : Expr → Code
  | .lit n => [.lit n]
  | .var x => [.var x]
  | .op kind a b => [.op kind (compile a) (compile b)]
  | .lam x body => [.clos x (compile body)]
  | .app fn arg => [.app (compile fn) (compile arg)]
  | .ite c t e => [.ite (compile c) (compile t) (compile e)]
  | .letE x v body => [.letE x (compile v) (compile body)]

end Lisp
