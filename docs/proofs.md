# The proofs tier

The engineering demos show that the ruleset builds software. This tier shows
that it builds mathematics. The theorems are small, they are verified by the
same three rules (`lean_library`, `lean_test`, later `lean_axiom_test`), and
they are chosen so that the *proof technique* differs between them.

## Inventory

| File | Theorem | Technique | Axioms |
| --- | --- | --- | --- |
| `Proofs/Sums.lean` | `sumOdds_eq`: the first `n` odd numbers sum to `n²` | induction, list lemmas | `propext`, `Quot.sound` |
| `Proofs/Sums.lean` | `odds_sum`: the list sum agrees with the recursive sum | induction with `List.range_succ` | `propext`, `Quot.sound` |
| `Proofs/Diagonal.lean` | `no_surjection_nat_bool`: no `Nat → Nat → Bool` is onto | diagonalization, `congrFun`, `Bool` cases | `propext` |
| `Proofs/Sqrt2.lean` | `no_sqrt2`: no `a * a = 2 * (b * b)` with `b ≠ 0` | infinite descent over `Nat.strongRecOn`, parity | `propext`, `Quot.sound` |
| `Proofs/Primes.lean` | `exists_prime_gt`: a prime above every bound (Euclid) | factorial, divisibility, minimal divisor | `propext`, `Classical.choice`, `Quot.sound` |
| `Proofs/Basic.lean` | `exists_prime_dvd`, `dvd_fact`, `two_dvd_mul_self` | helper lemmas for the above | as above |

The axiom column comes from Lean itself:

    cd proofs
    lean -R . /tmp/ax.lean     # /tmp/ax.lean holds `#print axioms ...` lines

Two facts are worth reading from that column. Cantor's argument needs neither
`Classical.choice` nor `Quot.sound`: the diagonal is a computation on `Bool`.
Euclid's argument *does* need `Classical.choice`, because "a composite number
has a divisor between one and itself" is not decidable without a search. A
later milestone, `lean_axiom_test`, turns this column into a build gate.

## Why the proofs are hand-rolled

The ruleset does not fetch Mathlib yet. Every lemma in `Proofs/Basic.lean` has a
Mathlib name:

| Hand-rolled | Mathlib |
| --- | --- |
| `Proofs.Prime` | `Nat.Prime` |
| `Proofs.fact`, `dvd_fact` | `Nat.factorial`, `Nat.dvd_factorial` |
| `Proofs.exists_prime_dvd` | `Nat.exists_prime_and_dvd` |
| `Proofs.exists_prime_gt` | `Nat.exists_infinite_primes` |
| `Proofs.no_sqrt2` | `irrational_sqrt_two` |
| `Proofs.no_surjection_nat_bool` | `Function.surjective` results in `Mathlib.Logic.Function.Basic` |

M1 brings `lean_prebuilt_library` and the Mathlib oleans from the cache. The tier
then keeps both versions: the hand-rolled file is the control, and the Mathlib
file is the measurement. If the cache works, the Mathlib version costs no
source build; if the cache is broken, the control still compiles the ruleset.

## Executable echoes

`Proofs/Test/Checks.lean` runs eleven checks on concrete numbers: factorials,
`sumOdds 100 = 10000`, the list sum against the recursive sum, trial division on
the primes below thirty, a brute-force search for a `sqrt 2` witness below
three hundred, and the diagonal of a concrete predicate function.

The theorems are statements about all naturals; the checks catch a change in
the definitions they are stated over.

## Rules for growth

1. A new theorem states its technique in the table above. Two induction proofs
   of the same shape are one theorem and one alias.
2. Every theorem has a runnable echo, or a comment that says why it cannot have
   one.
3. The axiom column is updated with `#print axioms`. A theorem whose axioms grew
   by accident is a finding, not an inconvenience.
4. The tier grows with the ruleset: M1 adds Mathlib versions, M4 adds the axiom
   gate, and the checks stay green through both.
