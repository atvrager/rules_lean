import Scheme.Ast
import Scheme.Env
import Scheme.Eval
import Scheme.Lexer
import Scheme.Parser
import Scheme.Prim
import Scheme.Sexp
import Scheme.Token

/-!
The root module: the whole interpreter library, in dependency order. The two
executable modules, `Scheme.Test.Eval` and `Scheme.Repl`, are not imported: each
defines a root-level `main`, as `lean --run` requires.
-/
