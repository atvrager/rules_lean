/-!
Cantor's diagonal argument, for the natural numbers and the boolean predicates.
The statement needs no number theory, and the proof needs no classical logic:
every step is a computation on `Bool`.
-/

namespace Proofs

/-- No function from the naturals onto the predicate functions. -/
theorem no_surjection_nat_bool :
    ¬ ∃ f : Nat → Nat → Bool, ∀ g : Nat → Bool, ∃ n, f n = g := by
  rintro ⟨f, hf⟩

  -- Flip the diagonal: `g n` differs from `f n n` at `n`.
  let g : Nat → Bool := fun n => !(f n n)
  obtain ⟨n, hn⟩ := hf g
  have h : f n n = !(f n n) := by
    simpa [g] using congrFun hn n
  cases hfnn : f n n <;> simp [hfnn] at h

end Proofs
