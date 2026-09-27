import Rtl.Types

/-!
A word-level netlist: an expression tree over input wires, and a runner that
evaluates every output.
-/

namespace Rtl

/-- A one-bit or word-level gate. -/
inductive Gate where
  | land
  | lor
  | lxor
  deriving Repr, DecidableEq

/-- An expression over the input wires `0 .. n-1`. -/
inductive Expr where
  | wire (index : Nat)
  | gate (kind : Gate) (left right : Expr)
  deriving Repr, DecidableEq

namespace Expr

/-- Evaluate an expression. A wire outside the inputs reads as zero. -/
def eval (inputs : List Word) : Expr → Word
  | .wire i => inputs[i]?.getD ⟨0, byte⟩
  | .gate kind l r =>
    let a := eval inputs l
    let b := eval inputs r
    match kind with
    | .land => a.land b
    | .lor => a.lor b
    | .lxor => a.lxor b

end Expr

/-- A combinational block: `inputs` wires, and one expression per output. -/
structure Netlist where
  inputs : Nat
  outputs : List Expr
  deriving Repr

namespace Netlist

/-- Evaluate every output of a block. -/
def run (block : Netlist) (values : List Word) : List Word :=
  block.outputs.map (Expr.eval values)

end Netlist

end Rtl
