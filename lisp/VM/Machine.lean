import VM.Word
namespace VM

/-- The stack machine: an explicit stack, an environment register, and no
compiler in the loop. The value type is deliberately separate from `Lisp.Value`,
so that F1 can relate two independent definitions. -/
inductive Value where
  | lit (n : Int)
  | clos (param : String) (body : Code) (env : List (String × Value))
deriving Repr

/-- A name-to-value association list. The innermost binding comes first. -/
abbrev Env := List (String × Value)

namespace Env

def lookup : Env → String → Option Value
  | [], _ => none
  | (name, value) :: rest, x =>
    if name == x then some value else lookup rest x

end Env

/-- Machine state. -/
structure State where
  /-- The operand stack. The top of the stack is the head. -/
  stack : List Value := []
  /-- The environment register. -/
  env : Env := []
deriving Repr

namespace State

/-- The integer on top of the stack. -/
def popInt (s : State) : Option (Int × State) :=
  match s.stack with
  | .lit n :: rest => some (n, { s with stack := rest })
  | _ => none

end State

/-- Run a code block from a state. `fuel` bounds the words executed. -/
def run (fuel : Nat) (s : State) : Code → Option State
  | [] => some s
  | w :: rest =>
    match fuel with
    | 0 => none
    | f + 1 =>
      match w with
      | .lit n => run f { s with stack := .lit n :: s.stack } rest
      | .var x =>
        match s.env.lookup x with
        | some v => run f { s with stack := v :: s.stack } rest
        | none => none
      | .clos p body => run f { s with stack := .clos p body s.env :: s.stack } rest
      | .op kind a b =>
        match run f s a, run f s b with
        | some s1, some s2 =>
          match s1.popInt, s2.popInt with
          | some (x, _), some (y, s2') =>
            run f { s2' with stack := .lit (kind.apply x y) :: s2'.stack } rest
          | _, _ => none
        | _, _ => none
      | .ite cond t e =>
        match run f s cond with
        | some s1 =>
          match s1.popInt with
          | some (n, s2) => run f s2 (if n == 0 then e else t)
          | none => none
        | none => none
      | .letE x value body =>
        match run f s value with
        | some s1 =>
          match s1.stack with
          | v :: rest' => run f { s1 with stack := rest', env := (x, v) :: s1.env } body
          | [] => none
        | none => none
      | .app fn arg =>
        match run f s fn, run f s arg with
        | some s1, some s2 =>
          match s1.stack, s2.stack with
          | .clos p body cenv :: _, v :: rest' =>
            run f { stack := rest', env := (p, v) :: cenv } body
          | _, _ => none
        | _, _ => none

end VM
