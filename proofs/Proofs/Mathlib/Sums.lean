import Mathlib.Data.Nat.Basic

namespace Proofs.MathlibProof

/-- The sum of the first `n` odd numbers. -/
def sumOdds : Nat → Nat
  | 0 => 0
  | n + 1 => sumOdds n + (2 * n + 1)

/-- The sum of the first `n` odd numbers is `n²`. -/
theorem sumOdds_eq (n : Nat) : sumOdds n = n * n := by
  induction n with
  | zero => rfl
  | succ n ih =>
    rw [sumOdds, ih]
    simp only [Nat.mul_succ, Nat.succ_mul, Nat.add_assoc]
    omega

end Proofs.MathlibProof
