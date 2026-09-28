import Cli
import Qq

namespace App

open Cli Qq

def sampleCmd : Cmd := `[Cli|
  app VIA run; ["0.1.0"]
  "Sample CLI command using lean4-cli."
] where run (_ : Parsed) : IO UInt32 := pure 0

def sampleQ : Q(Nat) := q(42)

def qqSample (n : Nat) : Nat := n + 1

end App
