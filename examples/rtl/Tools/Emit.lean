import Codegen.Emit
import Rtl.Netlist
import Rtl.Types

/-!
The command line tool of the demo project, the shape of a code generator: it
renders a block, and it reads the number of inputs from a file when one is
named on the command line. The file is a runfiles data dependency.
-/

namespace Rtl.Tools

/-- A small combinational block, to have something to render. -/
def demoBlock : Netlist :=
  { inputs := 2,
    outputs := [
      .gate .land (.wire 0) (.wire 1),
      .gate .lxor (.wire 0) (.wire 1),
      .gate .lor (.gate .land (.wire 0) (.wire 1)) (.wire 1)] }

/-- The number of inputs, read from the first line of a file. -/
def readInputs (path : String) : IO Nat := do
  let content ← IO.FS.readFile path
  let line := (content.splitOn "\n").headD "2"
  return (line.trimAscii.toString.toNat?).getD 2

def run (args : List String) : IO Unit := do
  let inputs ← match args with
    | path :: _ => readInputs path
    | [] => pure 2
  IO.print (render { demoBlock with inputs := inputs })

end Rtl.Tools

/-- `lean` and the linker both look for `main` in the root namespace. -/
def main (args : List String) : IO Unit := Rtl.Tools.run args
