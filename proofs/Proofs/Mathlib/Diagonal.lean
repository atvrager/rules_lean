import Mathlib.Logic.Function.Basic

namespace Proofs.MathlibProof

/-- No function from the naturals onto the predicate functions. -/
theorem no_surjection_nat_bool :
    ¬ ∃ f : Nat → Nat → Bool, Function.Surjective f := by
  rintro ⟨f, hf⟩
  let g : Nat → Bool := fun n => !(f n n)
  obtain ⟨n, hn⟩ := hf g
  have h : f n n = !(f n n) := by
    simpa [g] using congrFun hn n
  cases hfnn : f n n <;> simp [hfnn] at h

end Proofs.MathlibProof
