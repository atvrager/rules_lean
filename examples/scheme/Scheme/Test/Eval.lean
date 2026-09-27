import Scheme.Ast
import Scheme.Env
import Scheme.Eval
import Scheme.Lexer
import Scheme.Parser
import Scheme.Prim
import Scheme.Sexp
import Scheme.Token

/-!
Executable checks for the interpreter: the lexer (including comments and
escapes), the reader (nesting and the quote abbreviation, plus error cases), and
the evaluator (arithmetic, `if`, `let`, recursion, closures, `set!`, list and
string primitives, shadowing, and error cases).

Each check prints `ok <name>` when it passes. A failing check prints `FAIL` with
the observed value, and the process exits non-zero.
-/

open Scheme

namespace Scheme.Test

/-- Lex, read, compile and evaluate a source string. -/
def runString (src : String) : IO (Except String Value) := do
  match Lexer.lex src with
  | .error e => pure (.error e)
  | .ok toks =>
    match Parser.parse toks with
    | .error e => pure (.error e)
    | .ok sexps =>
      match Ast.compileProgram sexps with
      | .error e => pure (.error e)
      | .ok prog => (Eval.run prog Prim.initialEnv).run

/-- Report the outcome of one check. -/
private def report (name : String) (passed : Bool) (detail : String) : IO Bool := do
  if passed then
    IO.println s!"ok   {name}"
  else
    IO.println s!"FAIL {name}: {detail}"
  pure passed

/-- Check that a source string evaluates to the expected rendering. -/
private def checkEval (name : String) (src : String) (expected : String) : IO Bool := do
  let r ← runString src
  match r with
  | .ok v => report name (v.writeString == expected) s!"expected {expected}, got {v.writeString}"
  | .error e => report name false s!"expected {expected}, got error: {e}"

/-- Check that a source string is rejected somewhere in the pipeline. -/
private def checkError (name : String) (src : String) : IO Bool := do
  let r ← runString src
  match r with
  | .error _ => report name true ""
  | .ok v => report name false s!"expected an error, got {v.writeString}"

/-- Check the token list of a source string. -/
private def checkLex (name : String) (src : String) (expected : List Token) : IO Bool :=
  match Lexer.lex src with
  | .ok toks => report name (toks == expected) s!"got {repr toks}"
  | .error e => report name false s!"lex error: {e}"

/-- Check that a source string is not lexed. -/
private def checkLexError (name : String) (src : String) : IO Bool :=
  match Lexer.lex src with
  | .error _ => report name true ""
  | .ok toks => report name false s!"expected a lex error, got {repr toks}"

/-- Check the top-level forms of a source string. -/
private def checkParse (name : String) (src : String) (expected : List Sexp) : IO Bool :=
  match Lexer.lex src >>= Parser.parse with
  | .ok sexps => report name (sexps == expected) s!"got {repr sexps}"
  | .error e => report name false s!"parse error: {e}"

/-- Check that a source string is not parsed. -/
private def checkParseError (name : String) (src : String) : IO Bool :=
  match Lexer.lex src >>= Parser.parse with
  | .error _ => report name true ""
  | .ok sexps => report name false s!"expected a parse error, got {repr sexps}"

end Scheme.Test

open Scheme.Test

def main : IO Unit := do
  let fact := "(begin (define (fact n) (if (= n 0) 1 (* n (fact (- n 1))))) (fact 10))"
  let fib := "(begin (define (fib n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2))))) (fib 15))"
  let checks : List (IO Bool) := [
    checkLex "lexer-comment" "(+ 1 2) ; note\n" [.lparen, .symbol "+", .number 1, .number 2, .rparen],
    checkLex "lexer-literals" "#t #f \"hi\" -7 'x"
      [.boolean true, .boolean false, .string "hi", .number (-7), .quote, .symbol "x"],
    checkLex "lexer-string-escape" "\"a\\\"b\"" [.string "a\"b"],
    checkLexError "lexer-unterminated-string" "\"abc",
    checkParse "parser-nested" "(a (b c) 1)"
      [.list [.symbol "a", .list [.symbol "b", .symbol "c"], .atom (.number 1)]],
    checkParse "parser-quote" "'x" [.list [.symbol "quote", .symbol "x"]],
    checkParse "parser-quote-nested" "'(a b)"
      [.list [.symbol "quote", .list [.symbol "a", .symbol "b"]]],
    checkParseError "parser-error" "(a))",
    checkEval "arith-sum" "(+ 1 2 3)" "6",
    checkEval "arith-nested" "(- (* 4 5) 2 3)" "15",
    checkEval "division" "(/ 12 2 3)" "2",
    checkEval "modulo" "(modulo -7 3)" "2",
    checkEval "comparison" "(if (< 1 2) 10 20)" "10",
    checkEval "if-false" "(if (= 1 2) 10 20)" "20",
    checkEval "let" "(let ((x 2) (y 3)) (* x y))" "6",
    checkEval "let-shadow" "(let ((x 1)) (let ((x 2)) x))" "2",
    checkEval "recursion-fact" fact "3628800",
    checkEval "recursion-fib" fib "610",
    checkEval "closure-captures-env"
      "(begin (define (adder n) (lambda (x) (+ x n))) (define add5 (adder 5)) (add5 37))" "42",
    checkEval "set!" "(begin (define x 1) (set! x 42) x)" "42",
    checkEval "list-append" "(append (list 1 2) (list 3 4))" "(1 2 3 4)",
    checkEval "list-length" "(length (append (list 1 2) (list 3)))" "3",
    checkEval "list-car" "(car (cons 7 8))" "7",
    checkEval "list-cdr" "(cdr (cons 1 (list 2)))" "(2)",
    checkEval "list-null?" "(null? (cdr (list 1)))" "#t",
    checkEval "string-append" "(string-append \"ab\" \"cd\")" "\"abcd\"",
    checkEval "quote" "'(1 a \"s\")" "(1 a \"s\")",
    checkEval "not" "(not (= 1 2))" "#t",
    checkError "error-unbound" "(foo 1)",
    checkError "error-arity" "((lambda (x) x) 1 2)",
    checkError "error-division-by-zero" "(/ 1 0)"
  ]
  let results ← checks.mapM id
  let passed := (results.filter id).length
  if passed == results.length then
    IO.println s!"scheme: {passed} checks pass"
  else
    IO.println s!"scheme: {results.length - passed} of {results.length} checks FAIL"
    IO.Process.exit 1
