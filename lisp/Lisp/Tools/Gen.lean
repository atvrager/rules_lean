import Lisp.Expr

namespace Lisp.Tools

/-- Render an expression as a Lean source string. -/
def renderExpr : Expr → String
  | .lit n => s!"(.lit ({n}))"
  | .var x => s!"(.var \"{x}\")"
  | .op .add a b => s!"(.op .add {renderExpr a} {renderExpr b})"
  | .op .sub a b => s!"(.op .sub {renderExpr a} {renderExpr b})"
  | .op .mul a b => s!"(.op .mul {renderExpr a} {renderExpr b})"
  | .ite c t e => s!"(.ite {renderExpr c} {renderExpr t} {renderExpr e})"
  | .letE x v b => s!"(.letE \"{x}\" {renderExpr v} {renderExpr b})"
  | .lam x b => s!"(.lam \"{x}\" {renderExpr b})"
  | .app f a => s!"(.app {renderExpr f} {renderExpr a})"

/-- Emit a Lean module defining a generated expression. -/
def emitModule (modName : String) (defName : String) (e : Expr) : String :=
  s!"import Lisp.Expr\n\nnamespace {modName}\n\n/-- Generated expression. -/\ndef {defName} : Lisp.Expr :=\n  {renderExpr e}\n\nend {modName}\n"

end Lisp.Tools
