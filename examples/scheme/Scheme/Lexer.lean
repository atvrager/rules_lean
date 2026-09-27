import Scheme.Token

/-!
The lexer. It recognises whitespace, `;` line comments, parentheses, the quote
abbreviation, integers with an optional leading `-`, the booleans `#t` and `#f`,
string literals (with `\"` and `\\` escapes) and symbols. There are no block
comments. The scan carries explicit fuel because dropping a comment produces a
suffix the structural-recursion checker cannot relate to the input.
-/

open Scheme

namespace Scheme.Lexer

private def isSpace (c : Char) : Bool :=
  c == ' ' || c == '\n' || c == '\t' || c == '\r'

private def isDigit (c : Char) : Bool := c >= '0' && c <= '9'

/-- A character that ends a symbol. -/
private def isDelimiter (c : Char) : Bool :=
  isSpace c || c == '(' || c == ')' || c == '\'' || c == '"' || c == ';' || c == '#'

/-- Drop the rest of a `;` comment, up to and including its newline. -/
private def skipLine : List Char → List Char
  | [] => []
  | '\n' :: rest => rest
  | _ :: rest => skipLine rest

/-- Consume digits, returning them in source order together with the rest. -/
private def takeDigits (cs : List Char) (acc : List Char) : List Char × List Char :=
  match cs with
  | c :: rest => if isDigit c then takeDigits rest (c :: acc) else (acc.reverse, cs)
  | [] => (acc.reverse, [])

/-- Consume non-delimiter characters, returning the symbol text and the rest. -/
private def takeSymbol (cs : List Char) (acc : List Char) : String × List Char :=
  match cs with
  | c :: rest => if isDelimiter c then (String.ofList acc.reverse, cs) else takeSymbol rest (c :: acc)
  | [] => (String.ofList acc.reverse, [])

/-- Read a string body, the opening quote already consumed. -/
private def lexString : List Char → List Char → Except String (String × List Char)
  | [], _ => .error "unterminated string literal"
  | '"' :: rest, acc => .ok (String.ofList acc.reverse, rest)
  | '\\' :: c :: rest, acc =>
    if c == '"' || c == '\\' then lexString rest (c :: acc)
    else .error s!"invalid escape sequence: \\{c}"
  | c :: rest, acc => lexString rest (c :: acc)

private def go : Nat → List Char → List Token → Except String (List Token)
  | 0, _, _ => .error "lex: out of fuel"
  | fuel + 1, cs, acc =>
    match cs with
    | [] => .ok acc.reverse
    | c :: rest =>
      if isSpace c then go fuel rest acc
      else if c == ';' then go fuel (skipLine rest) acc
      else if c == '(' then go fuel rest (.lparen :: acc)
      else if c == ')' then go fuel rest (.rparen :: acc)
      else if c == '\'' then go fuel rest (.quote :: acc)
      else if c == '"' then
        match lexString rest [] with
        | .ok (s, rest') => go fuel rest' (.string s :: acc)
        | .error e => .error e
      else if c == '#' then
        match rest with
        | 't' :: rest' => go fuel rest' (.boolean true :: acc)
        | 'f' :: rest' => go fuel rest' (.boolean false :: acc)
        | _ => .error "expected `#t` or `#f` after `#`"
      else if isDigit c || (c == '-' && rest.head?.any isDigit) then
        let (digits, rest') := takeDigits rest []
        let text := String.ofList (c :: digits)
        match String.toInt? text with
        | some n => go fuel rest' (.number n :: acc)
        | none => .error s!"invalid number literal: {text}"
      else
        let (sym, rest') := takeSymbol (c :: rest) []
        go fuel rest' (.symbol sym :: acc)

/-- Tokenize a source string. Every token consumes at least one character, so
one more unit of fuel than there are characters is enough. -/
def lex (input : String) : Except String (List Token) :=
  go (input.length + 1) input.toList []

end Scheme.Lexer
