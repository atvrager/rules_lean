import Lisp.Expr

namespace Lisp

/-- Capture-avoiding substitution: substitute `val` for free occurrences of `x` in `e`. -/
def subst (x : String) (val : Expr) : Expr → Expr
  | .lit n => .lit n
  | .var y => if x = y then val else .var y
  | .op kind a b => .op kind (subst x val a) (subst x val b)
  | .lam y body => if x = y then .lam y body else .lam y (subst x val body)
  | .app fn arg => .app (subst x val fn) (subst x val arg)
  | .ite c t e => .ite (subst x val c) (subst x val t) (subst x val e)
  | .letE y v body =>
    if x = y then
      .letE y (subst x val v) body
    else
      .letE y (subst x val v) (subst x val body)

/-- Substitution on a closed expression does not change it. -/
theorem subst_not_mem (x : String) (val : Expr) (e : Expr) (h : x ∉ e.freeVars) :
    subst x val e = e := by
  induction e with
  | lit n => rfl
  | var y =>
    simp [Expr.freeVars] at h
    simp [subst, h]
  | op kind a b ih_a ih_b =>
    simp [Expr.freeVars] at h
    have ⟨ha, hb⟩ := h
    simp [subst, ih_a ha, ih_b hb]
  | lam y body ih =>
    simp [Expr.freeVars] at h
    by_cases hxy : x = y
    · subst hxy
      simp [subst]
    · have : x ∉ body.freeVars := by
        intro hm
        have hmem : x ∈ body.freeVars.erase y := (List.mem_erase_of_ne hxy).mpr hm
        exact h hmem
      simp [subst, hxy, ih this]
  | app fn arg ih_fn ih_arg =>
    simp [Expr.freeVars] at h
    have ⟨hf, ha⟩ := h
    simp [subst, ih_fn hf, ih_arg ha]
  | ite c t e ih_c ih_t ih_e =>
    simp [Expr.freeVars] at h
    have ⟨hc, ht, he⟩ := h
    simp [subst, ih_c hc, ih_t ht, ih_e he]
  | letE y v body ih_v ih_body =>
    simp [Expr.freeVars] at h
    have ⟨hv, hbody⟩ := h
    by_cases hxy : x = y
    · subst hxy
      simp [subst, ih_v hv]
    · have : x ∉ body.freeVars := by
        intro hm
        have hmem : x ∈ body.freeVars.erase y := (List.mem_erase_of_ne hxy).mpr hm
        exact hbody hmem
      simp [subst, hxy, ih_v hv, ih_body this]

end Lisp
