import Proofs.Basic
import Proofs.Diagonal
import Proofs.Primes
import Proofs.Sqrt2
import Proofs.Sums

/-!
Executable echoes of the theorems. The theorems are about all naturals; these
checks run the same computations on concrete numbers, so a change in the
definitions shows up in the test output.
-/

namespace Proofs.Test

/-- Trial division. True when no `d` in `2 .. n-1` divides `n`. -/
def isPrime (n : Nat) : Bool :=
  decide (2 ≤ n) && (List.range n).all (fun d => !(decide (2 ≤ d) && n % d == 0))

/-- The witness condition of the `sqrt 2` theorem, on concrete numbers. -/
def sqrt2Witness (a b : Nat) : Bool :=
  b != 0 && a * a == 2 * (b * b)

/-- Report one check. -/
def check (name : String) (ok : Bool) : IO Bool := do
  if ok then
    IO.println s!"ok   {name}"
  else
    IO.println s!"FAIL {name}"
  return ok

def runChecks : IO Unit := do
  let smallPrimes := (List.range 30).filter isPrime
  let diagonalExample (n : Nat) : Nat → Bool := fun k => k == n

  let results ← (
    check "fact-10" (fact 10 == 3628800) >>= fun a =>
    check "fact-grows" (fact 5 == 120 && fact 6 == 720) >>= fun b =>
    check "sum-odds-100" (sumOdds 100 == 10000) >>= fun c =>
    check "sum-odds-square" (sumOdds 37 == 37 * 37) >>= fun d =>
    check "odds-list" ((odds 100).sum == 10000) >>= fun e =>
    check "odds-list-agrees" ((odds 64).sum == sumOdds 64) >>= fun f =>
    check "is-prime" (isPrime 2 && isPrime 3 && isPrime 97) >>= fun g =>
    check "is-composite" (!isPrime 1 && !isPrime 4 && !isPrime 91) >>= fun h =>
    check "primes-below-30"
      (smallPrimes == [2, 3, 5, 7, 11, 13, 17, 19, 23, 29]) >>= fun i =>
    check "no-small-sqrt2-witness"
      (!(List.range 300).any (fun a =>
        (List.range 300).any (fun b => sqrt2Witness a b))) >>= fun j =>
    check "diagonal-differs"
      (((fun n => !(diagonalExample n n)) 7) != diagonalExample 7 7) >>= fun k =>
    pure [a, b, c, d, e, f, g, h, i, j, k])

  if results.all id then
    IO.println s!"proofs: {results.length} checks pass"
  else
    IO.println "proofs: FAILURES"
    IO.Process.exit 1

end Proofs.Test

/-- `lean --run` looks for `main` in the root namespace. -/
def main : IO Unit := Proofs.Test.runChecks
