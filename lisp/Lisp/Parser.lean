import Lisp.Expr

namespace Lisp

namespace Parser

/-- Token of a small Lisp expression. -/
inductive Token where
  | lparen
  | rparen
  | num (n : Int)
  | sym (s : String)
deriving Repr, BEq

/-- Lex a string into tokens. -/
partial def tokenize (s : String) : List Token :=
  let rec loop (chars : List Char) (acc : List Token) : List Token :=
    match chars with
    | [] => acc.reverse
    | c :: cs =>
      if c.isWhitespace then
        loop cs acc
      else if c == ';' then
        loop (cs.dropWhile (· != '\n')) acc
      else if c == '(' then
        loop cs (.lparen :: acc)
      else if c == ')' then
        loop cs (.rparen :: acc)
      else if c == '-' && match cs.head? with | some d => d.isDigit | none => false then
        let numChars := cs.takeWhile (·.isDigit)
        let rest := cs.dropWhile (·.isDigit)
        let n := (String.ofList numChars).toNat?.getD 0
        loop rest (.num (- n) :: acc)
      else if c.isDigit then
        let numChars := c :: cs.takeWhile (·.isDigit)
        let rest := cs.dropWhile (·.isDigit)
        let n := (String.ofList numChars).toNat?.getD 0
        loop rest (.num n :: acc)
      else
        let symChars := c :: cs.takeWhile (fun d => !d.isWhitespace && d != '(' && d != ')' && d != ';')
        let rest := cs.dropWhile (fun d => !d.isWhitespace && d != '(' && d != ')' && d != ';')
        loop rest (.sym (String.ofList symChars) :: acc)
  loop s.toList []

/-- Parse a single expression from tokens. -/
partial def parseExpr (toks : List Token) : Option (Expr × List Token) :=
  match toks with
  | [] => none
  | .num n :: rest => some (.lit n, rest)
  | .sym s :: rest => some (.var s, rest)
  | .lparen :: rest =>
    match parseList rest with
    | some (items, .rparen :: afterClose) =>
      match formOf items with
      | some e => some (e, afterClose)
      | none => none
    | _ => none
  | .rparen :: _ => none
where
  parseList (toks : List Token) : Option (List Expr × List Token) :=
    match toks with
    | [] => none
    | .rparen :: _ => some ([], toks)
    | _ =>
      match parseExpr toks with
      | some (e, rest) =>
        match parseList rest with
        | some (es, rest') => some (e :: es, rest')
        | none => none
      | none => none

  formOf (items : List Expr) : Option Expr :=
    match items with
    | [.var "+", a, b] => some (.op .add a b)
    | [.var "-", a, b] => some (.op .sub a b)
    | [.var "*", a, b] => some (.op .mul a b)
    | [.var "if", c, t, e] => some (.ite c t e)
    | [.var "let", .var x, v, body] => some (.letE x v body)
    | [.var "lam", .var x, body] => some (.lam x body)
    | [.var "lambda", .var x, body] => some (.lam x body)
    | [fn, arg] => some (.app fn arg)
    | _ => none

/-- Parse an expression from a source string. -/
def parse (s : String) : Option Expr :=
  match parseExpr (tokenize s) with
  | some (e, []) => some e
  | _ => none

end Parser

end Lisp
