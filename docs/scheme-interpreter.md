# The Scheme interpreter

`examples/scheme` is the second project-shaped demo, and the first one with
phases. It exists to test the ruleset against the way a real interpreter is
built: a pipeline of modules that each depend on the previous stage, one
command line program at the end, and a test suite that walks the whole path.

## The pipeline

```
"…source…" ──Lexer──▶ List Token ──Parser──▶ List Sexp ──compile──▶ List Ast
                                                                     │
                                          Eval.eval (fuel, Env) ◀────┘
                                                     │
                                       Env (association list, closures)
                                                     │
                                                    Prim
```

| Module | Job | What it proves about the ruleset |
| --- | --- | --- |
| `Scheme/Token.lean` | token type | a leaf module with no deps |
| `Scheme/Lexer.lean` | source to tokens | a stage boundary |
| `Scheme/Sexp.lean` | datum type | a second leaf, shared by the reader and the compiler |
| `Scheme/Parser.lean` | tokens to datums, `'x` reads as `(quote x)` | two deps, one of them shared |
| `Scheme/Ast.lean` | datums to core forms | a module many others import |
| `Scheme/Env.lean` | values, association environment, closures | recursion between `Value` and its environment |
| `Scheme/Prim.lean` | `+ - * / = < cons car cdr list append display` … | the only stage with effects |
| `Scheme/Eval.lean` | the evaluator, fuel-bounded | a mutual recursion over `EvalM` |
| `Scheme/Repl.lean` | `--eval`, `--file`, stdin | `lean_binary` with `srcs` and `data` |
| `Scheme/Test/Eval.lean` | 31 checks | `lean_test`, the interpreter path |
| `Scheme.lean` | root module | one target that compiles the library |

## What the interpreter demonstrates

    bazel test //examples/scheme:scheme_test        # 31 checks, interpreted
    bazel run  //examples/scheme:scheme -- --eval '(fact 20)'
    2432902008176640000
    bazel run  //examples/scheme:scheme -- --file examples/scheme/Fact.scm

The last one reads a file declared as `data`, so it runs only if the runfiles
of a `lean_binary` are complete.

## Core Lean shaped the design

The interpreter uses no Mathlib. Four consequences, from the build log:

1. `IO.getArgs` does not exist in Lean 4.34.1 core, not even with `import Std`.
   The supported convention is `def main (args : List String) : IO UInt32`,
   which receives the arguments after the file name and returns the exit code.
2. `display` and `newline` need effects, so the evaluator runs in
   `ExceptT String IO` while the lexer, the parser, and the compiler stay pure
   `Except String`.
3. Total recursion without `partial`: the lexer, the parser, and the evaluator
   all carry explicit fuel and recurse on it.
4. `define` must escape the evaluator, so `evalSeq` returns an environment and a
   value, and a closure carries its own name to be able to call itself. Mutual
   recursion between two top-level `define`s is not supported, and the file says
   so.

## Where it grows

| Ruleset feature | Interpreter change |
| --- | --- |
| Mathlib from the cache (M1) | a proof that the evaluator's arithmetic agrees with a reference over `Int` |
| import-graph scan (M0b) | the project collapses from eleven targets to one and keeps its cache behaviour |
| `lean_axiom_test` (M4) | a gate on that proof |
| persistent worker | the REPL's start-up cost, measured |
