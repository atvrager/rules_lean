namespace Scheme

/-- A self-evaluating literal: numbers, booleans and strings. -/
inductive Atom where
  | number (n : Int)
  | boolean (b : Bool)
  | string (s : String)
deriving Repr, BEq

/-- A symbolic expression: a literal, a symbol, or a list of expressions. -/
inductive Sexp where
  | atom (a : Atom)
  | symbol (s : String)
  | list (xs : List Sexp)
deriving Repr, BEq

end Scheme
