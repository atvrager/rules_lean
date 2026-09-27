import Scheme.Ast
import Scheme.Env
import Scheme.Prim

/-!
The evaluator. It is fuel-bounded, like the reference interpreter in `lisp/`, so
that it is total. The monad is `ExceptT String IO` because `display` and
`newline` write to standard output.

`eval` evaluates one expression in an environment. `evalSeq` evaluates a
sequence of forms — a body, or a whole program — and threads the environment, so
that a `define` or a `set!` in a sequence is visible to the forms after it. A
`define` outside a sequence has no environment to extend and is an error.
-/

open Scheme

namespace Scheme.Eval

/-- The evaluator's monad. -/
abbrev EvalM := ExceptT String IO

/-- The fuel used by `run`, enough for the demo programs and the checks. -/
def defaultFuel : Nat := 1000000

mutual
  /-- Evaluate an expression. `fuel` bounds the number of evaluation steps. -/
  def eval : Nat → Env → Ast → EvalM Value
    | 0, _, _ => throw "eval: out of fuel"
    | fuel + 1, env, ast =>
      match ast with
      | .lit a => pure (Value.ofAtom a)
      | .var x =>
        match env.lookup x with
        | some v => pure v
        | none => throw s!"unbound variable: {x}"
      | .quote s => pure (Value.ofSexp s)
      | .if c t e => do
        let cond ← eval fuel env c
        if cond.truthy then eval fuel env t else eval fuel env e
      | .lambda params body => pure (.closure "" params body env)
      | .define x _ => throw s!"define: {x} is only allowed in a sequence"
      | .set! x _ => throw s!"set!: {x} is only allowed in a sequence"
      | .begin body => do
        let (_, v) ← evalSeq fuel env body
        pure v
      | .let x v body => do
        let value ← eval fuel env v
        let (_, r) ← evalSeq fuel (Env.extend env x (Value.named x value)) body
        pure r
      | .apply fn args => do
        let f ← eval fuel env fn
        let vs ← evalArgs fuel env args
        match f with
        | .closure cname params body cenv =>
          let cenv := if cname.isEmpty then cenv else Env.extend cenv cname f
          match Env.bindParams cenv params vs with
          | .error e => throw e
          | .ok cenv' => do
            let (_, r) ← evalSeq fuel cenv' body
            pure r
        | .primitive name => Prim.call name vs
        | _ => throw s!"not a procedure: {f.writeString}"

  /-- Evaluate a sequence of forms, threading the environment so that `define`
  and `set!` affect the forms after them. The value of the sequence is the value
  of its last form; a trailing `define` or `set!` has the unspecified value. -/
  def evalSeq : Nat → Env → List Ast → EvalM (Env × Value)
    | 0, _, _ => throw "eval: out of fuel"
    | _, _, [] => throw "empty body"
    | fuel + 1, env, a :: rest =>
      match a with
      | .define x v => do
        let value ← eval fuel env v
        let env' := Env.extend env x (Value.named x value)
        if rest.isEmpty then pure (env', .nil) else evalSeq fuel env' rest
      | .set! x v => do
        let value ← eval fuel env v
        match env.set x value with
        | some env' =>
          if rest.isEmpty then pure (env', .nil) else evalSeq fuel env' rest
        | none => throw s!"set!: unbound variable: {x}"
      | _ => do
        let value ← eval fuel env a
        if rest.isEmpty then pure (env, value) else evalSeq fuel env rest

  /-- Evaluate argument expressions from left to right. -/
  def evalArgs : Nat → Env → List Ast → EvalM (List Value)
    | 0, _, _ => throw "eval: out of fuel"
    | _, _, [] => pure []
    | fuel + 1, env, a :: rest => do
      let v ← eval fuel env a
      let vs ← evalArgs fuel env rest
      pure (v :: vs)
end

/-- Evaluate a program with the default fuel and return the value of its last
form. `evalSeq` is the general entry point: it also returns the environment that
the program's definitions extended. -/
def run (prog : List Ast) (env : Env) : EvalM Value := do
  let (_, v) ← evalSeq defaultFuel env prog
  pure v

end Scheme.Eval
