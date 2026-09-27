import Rtl.Netlist

/-!
Emit a netlist as text, the shape of the SystemVerilog backend of a real
project: the model is in Lean, the file is a rendering of it.
-/

namespace Rtl

namespace Expr

/-- Render an expression in prefix form. -/
def render : Expr → String
  | .wire i => s!"w{i}"
  | .gate kind l r =>
    let name := match kind with
      | .land => "and"
      | .lor => "or"
      | .lxor => "xor"
    s!"({name} {l.render} {r.render})"

end Expr

/-- Render a whole block, one output per line. -/
def render (block : Netlist) : String :=
  let header := s!"block inputs={block.inputs}\n"
  let lines := block.outputs.map (fun e => s!"  {e.render}\n")
  header ++ String.join lines

end Rtl
