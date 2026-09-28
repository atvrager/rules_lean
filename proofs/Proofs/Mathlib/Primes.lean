import Mathlib.Data.Nat.Prime.Infinite

namespace Proofs.MathlibProof

/-- Euclid's theorem using Mathlib's Nat.exists_infinite_primes. -/
theorem exists_prime_gt (n : Nat) : ∃ p, Nat.Prime p ∧ n < p := by
  obtain ⟨p, hle, hp⟩ := Nat.exists_infinite_primes (n + 1)
  exact ⟨p, hp, by omega⟩

end Proofs.MathlibProof
