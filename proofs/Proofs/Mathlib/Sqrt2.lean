import Mathlib.Data.Nat.Basic
import Proofs.Basic

namespace Proofs.MathlibProof

/-- No natural square is twice a nonzero natural square. -/
theorem no_sqrt2 (a : Nat) : ¬ ∃ b : Nat, b ≠ 0 ∧ a * a = 2 * (b * b) := by
  induction a using Nat.strongRecOn with
  | ind a ih =>
    rintro ⟨b, hb, hab⟩
    have h2a : 2 ∣ a := Proofs.two_dvd_mul_self (by rw [hab]; exact ⟨b * b, rfl⟩)
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
    have hbsq : b * b = 2 * (c * c) := by
      have h1 : (2 * c) * (2 * c) = 2 * (b * b) := by rw [← hc]; exact hab
      have h2 : 2 * (2 * (c * c)) = 2 * (b * b) := by
        simpa [Nat.mul_assoc, Nat.mul_comm, Nat.mul_left_comm] using h1
      exact (Nat.mul_left_cancel (by omega : 0 < 2) h2).symm
    have h2b : 2 ∣ b := Proofs.two_dvd_mul_self (by rw [hbsq]; exact ⟨c * c, rfl⟩)
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
    exact ih c hclt ⟨d, hdne, hdc⟩

end Proofs.MathlibProof
