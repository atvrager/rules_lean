/-!
Core number theory for the proofs tier.

Mathlib has every lemma in this file. The file exists because the ruleset does
not fetch Mathlib yet, and it keeps the contrast visible: the same statements
become one-liners at M1, and the demo then measures the cache instead of the
proof.
-/

namespace Proofs

/-- `p` is prime: at least two, and its only divisors are one and itself. -/
def Prime (p : Nat) : Prop := 2 ≤ p ∧ ∀ m, m ∣ p → m = 1 ∨ m = p

/-- Two divides a square only if it divides the base. -/
theorem two_dvd_mul_self {a : Nat} (h : 2 ∣ a * a) : 2 ∣ a := by
  rcases Nat.mod_two_eq_zero_or_one a with h0 | h1
  · exact Nat.dvd_of_mod_eq_zero h0
  · have hmod : (a * a) % 2 = 1 := by simp [Nat.mul_mod, h1]
    have hzero : (a * a) % 2 = 0 := Nat.mod_eq_zero_of_dvd h
    omega

/-- The factorial of `n`. -/
def fact : Nat → Nat
  | 0 => 1
  | n + 1 => (n + 1) * fact n

/-- `n!` is at least one. -/
theorem fact_pos (n : Nat) : 1 ≤ fact n := by
  induction n with
  | zero => decide
  | succ n ih =>
    rw [fact]
    exact Nat.le_trans ih (Nat.le_mul_of_pos_left (fact n) (by omega))

/-- Every `i` in `1 .. n` divides `n!`. -/
theorem dvd_fact {i n : Nat} (hpos : 1 ≤ i) (hle : i ≤ n) : i ∣ fact n := by
  induction n with
  | zero => omega
  | succ n ih =>
    rw [fact]
    by_cases hsmall : i ≤ n
    · obtain ⟨t, ht⟩ := ih hsmall
      exact ⟨(n + 1) * t,
        by simp [ht, Nat.mul_assoc, Nat.mul_comm]⟩
    · have : i = n + 1 := by omega
      subst this
      exact Nat.dvd_mul_right (n + 1) (fact n)

/-- A number at least two that is not prime has a divisor strictly between one
and itself. -/
theorem exists_proper_dvd {n : Nat} (hge : 2 ≤ n) (hnot : ¬ Prime n) :
    ∃ d, d ∣ n ∧ 2 ≤ d ∧ d < n := by
  -- `¬ Prime n` with `2 ≤ n` gives a divisor that is neither one nor `n`.
  unfold Prime at hnot
  have hsome : ∃ m, m ∣ n ∧ m ≠ 1 ∧ m ≠ n := by
    apply Classical.byContradiction
    intro hnone
    apply hnot
    refine ⟨hge, fun m hm => ?_⟩
    apply Classical.byContradiction
    intro hcase
    exact hnone ⟨m, hm,
      (fun h1 => hcase (Or.inl h1)),
      (fun hn => hcase (Or.inr hn))⟩
  obtain ⟨m, hmdvd, hm1, hmn⟩ := hsome

  obtain ⟨k, rfl⟩ := hmdvd
  have hm0 : m ≠ 0 := by rintro rfl; simp at hge
  have hk0 : k ≠ 0 := by rintro rfl; simp at hge
  have hk1 : k ≠ 1 := by rintro rfl; exact hmn (Nat.mul_one m).symm
  have hm2 : 2 ≤ m := by omega
  have hk2 : 2 ≤ k := by omega
  have hlt : m < m * k := by
    have := Nat.mul_lt_mul_of_pos_left (show 1 < k by omega) (show 0 < m by omega)
    simpa [Nat.mul_one] using this
  exact ⟨m, ⟨k, rfl⟩, hm2, hlt⟩

/-- Every number at least two has a prime divisor. -/
theorem exists_prime_dvd {n : Nat} (hge : 2 ≤ n) : ∃ p, Prime p ∧ p ∣ n := by
  induction n using Nat.strongRecOn with
  | ind n ih =>
    by_cases hprime : Prime n
    · exact ⟨n, hprime, Nat.dvd_refl n⟩
    · obtain ⟨d, hdvd, hd2, hdlt⟩ := exists_proper_dvd hge hprime
      obtain ⟨p, hp, hpd⟩ := ih d hdlt hd2
      exact ⟨p, hp, Nat.dvd_trans hpd hdvd⟩

end Proofs
