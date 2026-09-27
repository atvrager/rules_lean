/-!
Sums of the first `n` odd numbers, twice: once by recursion on `Nat`, once over
a list. The list version is the executable one.
-/

namespace Proofs

/-- The sum of the first `n` odd numbers. -/
def sumOdds : Nat → Nat
  | 0 => 0
  | n + 1 => sumOdds n + (2 * n + 1)

/-- The first `n` odd numbers. -/
def odds (n : Nat) : List Nat := (List.range n).map (fun i => 2 * i + 1)

/-- The sum of the first `n` odd numbers is `n²`. -/
theorem sumOdds_eq (n : Nat) : sumOdds n = n * n := by
  induction n with
  | zero => rfl
  | succ n ih =>
    rw [sumOdds, ih]
    simp only [Nat.mul_succ, Nat.succ_mul, Nat.add_assoc]
    omega

/-- The list of odd numbers sums to the same value. -/
theorem odds_sum (n : Nat) : (odds n).sum = sumOdds n := by
  induction n with
  | zero => rfl
  | succ n ih =>
    have hstep : odds (n + 1) = odds n ++ [2 * n + 1] := by
      simp [odds, List.range_succ, List.map_append]
    rw [hstep, List.sum_append, ih]
    simp [sumOdds]

end Proofs
