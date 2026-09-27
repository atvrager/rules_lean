import Proofs.Basic

/-!
Euclid's theorem: there is a prime above every bound. `n! + 1` is not divisible
by any number in `1 .. n`, so a prime divisor of it is larger than `n`.
-/

namespace Proofs

theorem exists_prime_gt (n : Nat) : ∃ p, Prime p ∧ n < p := by
  have hge : 2 ≤ fact n + 1 := by
    have := fact_pos n
    omega
  obtain ⟨p, hp, hpdvd⟩ := exists_prime_dvd hge
  have h2p : 2 ≤ p := hp.1

  refine ⟨p, hp, Nat.lt_of_not_le ?_⟩
  intro hle
  have hp1 : 1 ≤ p := by omega
  have hdvdFact : p ∣ fact n := dvd_fact hp1 (by omega)
  have hone : p ∣ 1 := (Nat.dvd_add_iff_right hdvdFact).mpr hpdvd
  have hpOne : p = 1 := Nat.dvd_one.mp hone
  omega

end Proofs
