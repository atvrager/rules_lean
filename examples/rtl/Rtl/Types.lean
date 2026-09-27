/-!
Words and bit widths of the little RTL model.
-/

namespace Rtl

/-- A bit width. `bits` is at least one. -/
structure Width where
  bits : Nat
  deriving Repr, DecidableEq

/-- The width of one byte, the unit of the model. -/
def byte : Width := ⟨8⟩

/-- A value of a fixed width. Values wrap, as in hardware. -/
structure Word where
  value : Nat
  width : Width
  deriving Repr, DecidableEq

namespace Word

/-- Build a word, wrapping the value to the width. -/
def ofNat (w : Width) (n : Nat) : Word := ⟨n % 2 ^ w.bits, w⟩

/-- Bitwise and, at the width of the left operand. -/
def land (a b : Word) : Word := ofNat a.width (a.value &&& b.value)

/-- Bitwise or. -/
def lor (a b : Word) : Word := ofNat a.width (a.value ||| b.value)

/-- Bitwise exclusive or. -/
def lxor (a b : Word) : Word := ofNat a.width (a.value ^^^ b.value)

end Word
end Rtl
