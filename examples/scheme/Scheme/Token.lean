namespace Scheme

/-- A lexical token of the Scheme surface syntax. -/
inductive Token where
  | lparen
  | rparen
  | quote
  | number (n : Int)
  | boolean (b : Bool)
  | string (s : String)
  | symbol (s : String)
deriving Repr, BEq

end Scheme
