namespace VM

/-!
Words of the stack machine.

The machine is structured: a word holds the code of its own sub-blocks, so the
machine needs no program counter and no jump offsets. Flat bytecode with `jmp`
and `jz` arrives at F2, with the native executable.
-/

/-- Arithmetic operations of the machine. -/
inductive Op where
  | add
  | sub
  | mul
deriving Repr, DecidableEq

/-- A word of the machine. -/
inductive Word where
  /-- Push an integer literal. -/
  | lit (n : Int)
  /-- Push the value of a name from the environment. -/
  | var (name : String)
  /-- Push a closure over `param` and `body`, in the current environment. -/
  | clos (param : String) (body : List Word)
  /-- Run an operation on two sub-expressions. -/
  | op (kind : Op) (left right : List Word)
  /-- Run the condition, then one branch. -/
  | ite (cond then_ else_ : List Word)
  /-- Bind a name to the value of a sub-expression while the body runs. -/
  | letE (name : String) (value body : List Word)
  /-- Apply the value of `fn` to the value of `arg`. -/
  | app (fn arg : List Word)
deriving Repr

/-- A sequence of words. -/
abbrev Code := List Word

namespace Op

/-- Apply an operation to two integers. -/
def apply : Op → Int → Int → Int
  | .add, a, b => a + b
  | .sub, a, b => a - b
  | .mul, a, b => a * b

end Op

end VM
