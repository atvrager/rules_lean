import Mathlib.Data.Finsupp.Basic
import Lisp.Expr
import Lisp.Eval

namespace Lisp

open Classical

/-- Finite environments using Mathlib Finsupp. -/
instance (priority := low) {α : Type} : Zero (Option α) := ⟨none⟩

abbrev FEnv (α : Type) := String →₀ Option α

namespace FEnv

noncomputable def empty {α : Type} : FEnv α := 0

noncomputable def lookup {α : Type} (env : FEnv α) (x : String) : Option α :=
  env x

noncomputable def extend {α : Type} (env : FEnv α) (x : String) (v : α) : FEnv α :=
  Finsupp.update env x (some v)

def domain {α : Type} (env : FEnv α) : Finset String :=
  env.support

theorem lookup_extend_eq {α : Type} (env : FEnv α) (x : String) (v : α) :
    lookup (extend env x v) x = some v := by
  simp [lookup, extend, Finsupp.update]

theorem lookup_extend_ne {α : Type} (env : FEnv α) {x y : String} (h : y ≠ x) (v : α) :
    lookup (extend env x v) y = lookup env y := by
  simp [lookup, extend, Finsupp.update_apply, h]

end FEnv

end Lisp
