import Proofs.Basic

/-!
The square root of two is not rational, in the form that needs no rationals: no
natural square is twice a nonzero natural square. The proof is an infinite
descent. If `a` is the least witness, then `a` is even, `b` is even, and their
halves are a smaller witness.
-/

namespace Proofs

/-- Halving a witness. From `a * a = 2 * (b * b)` with `b ≠ 0`, both `a` and
`b` are even, and their halves satisfy the same equation with a smaller left
side. -/
theorem sqrt2_descend {a b : Nat} (hb : b ≠ 0) (hab : a * a = 2 * (b * b)) :
    ∃ c d, d ≠ 0 ∧ c < a ∧ c * c = 2 * (d * d) := by
  -- `2 ∣ a * a` because that product is `2 * (b * b)`.
  have h2a : 2 ∣ a := two_dvd_mul_self (by rw [hab]; exact ⟨b * b, rfl⟩)
  obtain ⟨c, hc⟩ := h2a
  have hcpos : 0 < c := by
    rcases Nat.eq_zero_or_pos c with h0 | hpos
    · subst h0
      rw [Nat.mul_zero] at hc
      subst hc
      have hb0 : b * b = 0 := by omega
      rcases Nat.mul_eq_zero.mp hb0 with h | h
      · exact absurd h hb
      · exact absurd h hb
    · exact hpos

  -- With `a = 2 * c` the equation becomes `b * b = 2 * (c * c)`.
  have hbsq : b * b = 2 * (c * c) := by
    have h1 : (2 * c) * (2 * c) = 2 * (b * b) := by rw [← hc]; exact hab
    have h2 : 2 * (2 * (c * c)) = 2 * (b * b) := by
      simpa [Nat.mul_assoc, Nat.mul_comm, Nat.mul_left_comm] using h1
    exact (Nat.mul_left_cancel (by omega : 0 < 2) h2).symm

  -- `b` is even as well, so `b = 2 * d` and `c * c = 2 * (d * d)`.
  have h2b : 2 ∣ b := two_dvd_mul_self (by rw [hbsq]; exact ⟨c * c, rfl⟩)
  obtain ⟨d, hd⟩ := h2b
  have hdne : d ≠ 0 := by
    rintro rfl
    rw [Nat.mul_zero] at hd
    exact hb hd
  have hdc : c * c = 2 * (d * d) := by
    have h1 : (2 * d) * (2 * d) = 2 * (c * c) := by rw [← hd]; exact hbsq
    have h2 : 2 * (2 * (d * d)) = 2 * (c * c) := by
      simpa [Nat.mul_assoc, Nat.mul_comm, Nat.mul_left_comm] using h1
    exact (Nat.mul_left_cancel (by omega : 0 < 2) h2).symm

  have hclt : c < a := by
    rw [hc]
    omega
  exact ⟨c, d, hdne, hclt, hdc⟩

/-- No natural square is twice a nonzero natural square. -/
theorem no_sqrt2 (a : Nat) : ¬ ∃ b : Nat, b ≠ 0 ∧ a * a = 2 * (b * b) := by
  induction a using Nat.strongRecOn with
  | ind a ih =>
    rintro ⟨b, hb, hab⟩
    obtain ⟨c, d, hd, hclt, hcd⟩ := sqrt2_descend hb hab
    exact ih c hclt ⟨d, hd, hcd⟩

end Proofs
