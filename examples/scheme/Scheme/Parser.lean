import Scheme.Token
import Scheme.Sexp

/-!
The reader. Parentheses nest arbitrarily; `'x` abbreviates `(quote x)`.
The parser is a small stack machine driven by explicit fuel, so that it is
total.
-/

open Scheme

namespace Scheme.Parser

/-- An open parenthesis accumulating elements, or a pending quote. -/
private inductive Frame where
  | list (acc : List Sexp)
  | quote

/-- Deliver a completed value: close the pending quotes above it, then either
extend the enclosing frame or record a top-level form. -/
private def deliver : Sexp → List Frame → List Sexp → List Frame × List Sexp
  | v, .quote :: rest, done => deliver (.list [.symbol "quote", v]) rest done
  | v, [], done => ([], v :: done)
  | v, .list acc :: outer, done => (.list (v :: acc) :: outer, done)

private def parseLoop : Nat → List Token → List Frame → List Sexp → Except String (List Sexp)
  | 0, _, _, _ => .error "parse: out of fuel"
  | fuel + 1, toks, frames, done =>
    match toks with
    | [] =>
      if frames.isEmpty then .ok done.reverse
      else .error "unexpected end of input"
    | .lparen :: rest => parseLoop fuel rest (.list [] :: frames) done
    | .rparen :: rest =>
      match frames with
      | .list acc :: outer =>
        let (frames', done') := deliver (.list acc.reverse) outer done
        parseLoop fuel rest frames' done'
      | _ => .error "unexpected `)`"
    | .quote :: rest => parseLoop fuel rest (.quote :: frames) done
    | .number n :: rest =>
      let (frames', done') := deliver (.atom (.number n)) frames done
      parseLoop fuel rest frames' done'
    | .boolean b :: rest =>
      let (frames', done') := deliver (.atom (.boolean b)) frames done
      parseLoop fuel rest frames' done'
    | .string s :: rest =>
      let (frames', done') := deliver (.atom (.string s)) frames done
      parseLoop fuel rest frames' done'
    | .symbol s :: rest =>
      let (frames', done') := deliver (.symbol s) frames done
      parseLoop fuel rest frames' done'

/-- Parse a token list into the list of top-level forms. -/
def parse (toks : List Token) : Except String (List Sexp) :=
  parseLoop (4 * toks.length + 8) toks [] []

end Scheme.Parser
