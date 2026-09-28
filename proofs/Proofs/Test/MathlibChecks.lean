import Proofs.Mathlib.Diagonal
import Proofs.Mathlib.Primes
import Proofs.Mathlib.Sqrt2
import Proofs.Mathlib.Sums

namespace Proofs.Test.MathlibChecks

def check (name : String) (ok : Bool) : IO Bool := do
  if ok then
    IO.println s!"ok   {name}"
  else
    IO.println s!"FAIL {name}"
  return ok

def runChecks : IO Unit := do
  let results ← (
    check "mathlib-sumOdds-100" (Proofs.MathlibProof.sumOdds 100 == 10000) >>= fun a =>
    check "mathlib-sumOdds-square" (Proofs.MathlibProof.sumOdds 37 == 37 * 37) >>= fun b =>
    check "mathlib-prime-17" (decide (Nat.Prime 17)) >>= fun c =>
    pure [a, b, c])

  if results.all id then
    IO.println s!"mathlib proofs: {results.length} checks pass"
  else
    IO.println "mathlib proofs: FAILURES"
    IO.Process.exit 1

end Proofs.Test.MathlibChecks

def main : IO Unit := Proofs.Test.MathlibChecks.runChecks
