import Scheme.Sexp

/-!
The core language and its compiler. `compile` turns data into an `Ast`: procedure
calls become `apply`, `'x` becomes `quote`, `(let ((x e)) body)` becomes `let`
(several bindings nest, i.e. they behave like `let*`), and
`(define (f x) body)` is sugar for `(define f (lambda (x) body))`.

A body is a list of forms so that `lambda`, `let` and `begin` sequence
correctly; `define` and `set!` are only meaningful in such a sequence, which is
where the evaluator handles them.
-/

open Scheme

namespace Scheme

/-- The core forms. -/
inductive Ast where
  | lit (a : Atom)
  | var (name : String)
  | quote (s : Sexp)
  | if (c t e : Ast)
  | lambda (params : List String) (body : List Ast)
  | define (name : String) (value : Ast)
  | set! (name : String) (value : Ast)
  | begin (body : List Ast)
  | let (name : String) (value : Ast) (body : List Ast)
  | apply (fn : Ast) (args : List Ast)
deriving Repr

end Scheme

namespace Scheme.Ast

open Scheme

/-- Compile a parameter list, which must be symbols. -/
private def compileParams : List Sexp → Except String (List String)
  | [] => .ok []
  | .symbol x :: rest => do
    let ps ← compileParams rest
    pure (x :: ps)
  | _ => .error "lambda: parameters must be symbols"

mutual
  /-- Compile a datum to an expression. -/
  def compile : Sexp → Except String Ast
    | .atom a => .ok (.lit a)
    | .symbol x => .ok (.var x)
    | .list xs => compileForm xs

  /-- Compile a list form: a special form if its head is a keyword, otherwise a
  procedure call. -/
  private def compileForm (xs : List Sexp) : Except String Ast :=
    match xs with
    | [] => .error "cannot compile the empty list"
    | .symbol "quote" :: rest =>
      match rest with
      | [s] => .ok (.quote s)
      | _ => .error "quote: expected exactly one form"
    | .symbol "if" :: rest =>
      match rest with
      | [c, t] => do
        let c' ← compile c
        let t' ← compile t
        pure (.if c' t' (.lit (.boolean false)))
      | [c, t, e] => do
        let c' ← compile c
        let t' ← compile t
        let e' ← compile e
        pure (.if c' t' e')
      | _ => .error "if: expected 2 or 3 forms"
    | .symbol "lambda" :: .list ps :: body => do
      let params ← compileParams ps
      let b ← compileSequence body "lambda: empty body"
      pure (.lambda params b)
    | .symbol "lambda" :: _ => .error "lambda: expected a parameter list"
    | .symbol "define" :: .symbol x :: [v] => do
      let v' ← compile v
      pure (.define x v')
    | .symbol "define" :: .list (.symbol f :: ps) :: body => do
      let params ← compileParams ps
      let b ← compileSequence body "define: empty body"
      pure (.define f (.lambda params b))
    | .symbol "define" :: _ => .error "define: expected a name and one form"
    | .symbol "set!" :: .symbol x :: [v] => do
      let v' ← compile v
      pure (.set! x v')
    | .symbol "set!" :: _ => .error "set!: expected a name and one form"
    | .symbol "begin" :: body => do
      let b ← compileSequence body "begin: empty body"
      pure (.begin b)
    | .symbol "let" :: .list bindings :: body => do
      let b ← compileSequence body "let: empty body"
      compileLet bindings b
    | .symbol "let" :: _ => .error "let: expected a binding list"
    | fn :: args => do
      let f ← compile fn
      let as ← compileBody args
      pure (.apply f as)

  /-- Compile a non-empty sequence of forms. -/
  private def compileSequence (xs : List Sexp) (emptyMsg : String) : Except String (List Ast) :=
    match xs with
    | [] => .error emptyMsg
    | x :: rest => do
      let a ← compile x
      let as ← compileBody rest
      pure (a :: as)

  /-- Compile the remaining forms of a sequence, which may be empty. -/
  private def compileBody : List Sexp → Except String (List Ast)
    | [] => .ok []
    | x :: rest => do
      let a ← compile x
      let as ← compileBody rest
      pure (a :: as)

  /-- Compile `let` bindings, nesting them in order around the body. -/
  private def compileLet (bindings : List Sexp) (body : List Ast) : Except String Ast :=
    match bindings with
    | [] =>
      match body with
      | [a] => .ok a
      | _ => .ok (.begin body)
    | .list [.symbol x, e] :: rest => do
      let v ← compile e
      match rest with
      | [] => pure (.let x v body)
      | _ => do
        let inner ← compileLet rest body
        pure (.let x v [inner])
    | _ => .error "let: expected bindings of the form (name form)"
end

/-- Compile a program: a sequence of top-level forms. -/
def compileProgram (sexps : List Sexp) : Except String (List Ast) := compileBody sexps

end Scheme.Ast
