import Scheme.Ast

/-!
Runtime values and environments. An environment is an association list with the
innermost binding first. The value type has to go beyond numbers, booleans,
strings, closures and primitive names: `cons`/`car`/`cdr` need pairs, `quote`
needs symbols, and `display`/`newline` need an unspecified result, which is
represented by the empty list.
-/

open Scheme

namespace Scheme

/-- A runtime value. -/
inductive Value where
  | number (n : Int)
  | boolean (b : Bool)
  | string (s : String)
  | symbol (name : String)
  /-- The empty list; also the result of forms whose value is unspecified. -/
  | nil
  /-- A cons cell. -/
  | pair (car cdr : Value)
  /-- A user procedure: the name it was defined under (empty for an anonymous
  `lambda`), its parameters, its body, and the environment it captured. The name
  lets a recursive procedure refer to itself. -/
  | closure (name : String) (params : List String) (body : List Ast)
      (env : List (String × Value))
  /-- A primitive procedure, dispatched by name in `Scheme.Prim`. -/
  | primitive (name : String)
deriving Repr

/-- A name-to-value association list. The innermost binding comes first. -/
abbrev Env := List (String × Value)

namespace Value

/-- Scheme truth: only `#f` is false. -/
def truthy : Value → Bool
  | .boolean false => false
  | _ => true

mutual
  /-- Render a value: numbers, booleans, symbols, `(a b . c)` for pairs, and
  `#<procedure ...>` for procedures. With `quoted`, strings show their quotes,
  which is how the REPL prints a result. -/
  def render (quoted : Bool) : Value → String
    | .number n => toString n
    | .boolean b => if b then "#t" else "#f"
    | .string s => if quoted then "\"" ++ s ++ "\"" else s
    | .symbol s => s
    | .nil => "()"
    | .pair c d => "(" ++ render quoted c ++ renderTail quoted d
    | .closure _ params _ _ => "#<procedure (" ++ String.intercalate " " params ++ ")>"
    | .primitive n => "#<primitive " ++ n ++ ">"

  /-- Render the rest of a list whose first element has been rendered. -/
  def renderTail (quoted : Bool) : Value → String
    | .nil => ")"
    | .pair c d => " " ++ render quoted c ++ renderTail quoted d
    | other => " . " ++ render quoted other ++ ")"
end

/-- The rendering used by `display`. -/
def displayString (v : Value) : String := render false v

/-- The rendering used by the REPL and by error messages. -/
def writeString (v : Value) : String := render true v

/-- Give a procedure the name it is being bound to, so that its own body can
refer to it. -/
def named (name : String) : Value → Value
  | .closure _ params body env => .closure name params body env
  | v => v

/-- A literal as a value. -/
def ofAtom : Atom → Value
  | .number n => .number n
  | .boolean b => .boolean b
  | .string s => .string s

mutual
  /-- A quoted datum as a value. -/
  def ofSexp : Sexp → Value
    | .atom a => ofAtom a
    | .symbol s => .symbol s
    | .list xs => ofList xs

  /-- A quoted datum list as a proper Scheme list. -/
  def ofList : List Sexp → Value
    | [] => .nil
    | s :: rest => .pair (ofSexp s) (ofList rest)
end

end Value

namespace Env

/-- The value bound to a name, if any. -/
def lookup : Env → String → Option Value
  | [], _ => none
  | (name, v) :: rest, x => if name == x then some v else lookup rest x

/-- Add an innermost binding. A shadowed name becomes unreachable. -/
def extend (env : Env) (name : String) (value : Value) : Env := (name, value) :: env

/-- Bind parameters to arguments in front of `env`, failing on an arity
mismatch. -/
def bindParams (env : Env) (names : List String) (values : List Value) : Except String Env :=
  if names.length == values.length then
    .ok ((names.zip values).reverse ++ env)
  else
    .error s!"arity mismatch: expected {names.length} argument(s), got {values.length}"

/-- Overwrite the innermost binding of a name, if it is bound. -/
def set : Env → String → Value → Option Env
  | [], _, _ => none
  | (name, v) :: rest, x, val =>
    if name == x then some ((name, val) :: rest)
    else Option.map (fun rest' => (name, v) :: rest') (set rest x val)

end Env

end Scheme
