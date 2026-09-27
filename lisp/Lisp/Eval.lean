import Lisp.Expr

open VM
namespace Lisp

/-- The reference evaluator: a small-step-free interpreter over an association
environment. F1 proves that the machine agrees with it. -/
inductive Value where
  | lit (n : Int)
  | clos (param : String) (body : Expr) (env : List (String × Value))
deriving Repr

/-- A name-to-value association list. The innermost binding comes first. -/
abbrev Env := List (String × Value)

namespace Env

/-- The value bound to a name, if any. -/
def lookup : Env → String → Option Value
  | [], _ => none
  | (name, value) :: rest, x =>
    if name == x then some value else lookup rest x

/-- Extend the environment. A shadowed name becomes unreachable. -/
def extend (env : Env) (name : String) (value : Value) : Env := (name, value) :: env

end Env

/-- Evaluate an expression. `fuel` bounds the number of recursive steps. -/
def eval : Nat → Env → Expr → Option Value
  | 0, _, _ => none
  | fuel + 1, env, expr =>
    match expr with
    | .lit n => some (.lit n)
    | .var x => env.lookup x
    | .op kind a b =>
      match eval fuel env a, eval fuel env b with
      | some (.lit x), some (.lit y) => some (.lit (kind.apply x y))
      | _, _ => none
    | .lam x body => some (.clos x body env)
    | .app fn arg =>
      match eval fuel env fn, eval fuel env arg with
      | some (.clos x body cenv), some v => eval fuel (Env.extend cenv x v) body
      | _, _ => none
    | .ite cond t e =>
      match eval fuel env cond with
      | some (.lit n) => if n == 0 then eval fuel env e else eval fuel env t
      | _ => none
    | .letE x v body =>
      match eval fuel env v with
      | some value => eval fuel (Env.extend env x value) body
      | none => none

end Lisp
