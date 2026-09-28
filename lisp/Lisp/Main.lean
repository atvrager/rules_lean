import Lisp.Compile
import Lisp.Expr
import Lisp.Parser
import VM.Machine

open Lisp VM

namespace Lisp.Main

def runFile (path : String) : IO UInt32 := do
  let contents ← IO.FS.readFile path
  match Parser.parse contents with
  | none =>
    IO.eprintln s!"error: parse failure in {path}"
    return 1
  | some expr =>
    match run 100000 {} (compile expr) with
    | none =>
      IO.eprintln s!"error: execution failed in {path}"
      return 1
    | some s =>
      match s.stack.head? with
      | some (.lit n) =>
        IO.println s!"{n}"
        return 0
      | some (.clos ..) =>
        IO.println "<closure>"
        return 0
      | none =>
        IO.eprintln s!"error: empty stack after execution"
        return 1

end Lisp.Main

def main (args : List String) : IO UInt32 := do
  let path := match args with
    | p :: _ => p
    | [] => "lisp/prog.lisp"
  let fp : System.FilePath := path
  if ← fp.pathExists then
    Lisp.Main.runFile fp.toString
  else
    let altFp : System.FilePath := s!"lisp/{path}"
    if ← altFp.pathExists then
      Lisp.Main.runFile altFp.toString
    else
      IO.eprintln s!"error: cannot find {path}"
      return 1
