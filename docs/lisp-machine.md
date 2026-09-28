# The Lisp machine: the long-term test suite

The repository has three test tiers.

| Tier | What it is | Where |
| --- | --- | --- |
| Unit | one rule, one feature, seconds | `e2e/` (one bzlmod module per case) |
| Integration | a real Lean project that grows with the ruleset | `lisp/` (the Lisp machine) |
| Field | projects outside this repository that use the ruleset | not in this repository |

The Lisp machine exists for one reason: a ruleset with only toy tests passes its
own tests and fails on real code. It is a small Lisp interpreter with a
correctness proof, written in Lean 4 against Mathlib. Every Lean feature the
ruleset gains gets a new piece of the machine, and every piece stays in the
build forever. When the ruleset breaks, the machine breaks.

## Goal

Build a three-part system and prove the parts agree:

1. `Eval`: a high-level evaluator for a small Lisp (atoms, `lambda`, `if`, `let`,
   application, closures).
2. `VM`: a stack machine (push, arithmetic, load, store, call, ret).
3. `Compile`: a compiler from the Lisp core to VM words.

The theorem is `run (compile e) ρ = eval e ρ`. A Lisp machine was chosen over a
Forth machine for this reason: the interesting content of the proof is
substitution, environments, and closure environments, where Mathlib has lemmas.
Stack arithmetic alone would prove nothing.

## Content

What exists at F0:

```
lisp/
  BUILD.bazel             one target per module
  VM/Word.lean            Word, Code, Op
  Lisp/Expr.lean          Expr, freeVars
  Lisp/Eval.lean          Value, Env, eval (fuel-bounded)
  VM/Machine.lean         Value, Env, State, run (fuel-bounded)
  Lisp/Compile.lean       compile : Expr -> Code
  Lisp.lean               root module, imports the rest
  Lisp/Test/Eval.lean     10 checks: eval and run agree on every sample
```

What F1 and later add:

```
  Lisp/Env.lean           environments as finite maps (Mathlib Finsupp)
  Lisp/Subst.lean         capture-avoiding substitution, substitution lemmas
  Lisp/Correctness.lean   run (compile e) ρ = eval e ρ
  Lisp/Tools/Gen.lean     emits a program as Lean source (ruleset: generated srcs)
  VM/Flat.lean            flat bytecode: jmp, jz, pc
  VM/Cost.lean            instruction count, cost of a compiled expression
```

F0 needed one target per module, because the rule did not read `import` lines
yet. At M0b, the ruleset scans the import graph and the machine collapses to
one target (`//lisp:lisp`), keeping its cache behaviour.

### Where Mathlib does real work

- `Finsupp` and `Finset` for environments: domain, update, agreement of two
  environments on a variable set.
- `List` and `List.Perm` for the stack: pushing a compiled expression permutes
  the stack in a known way.
- `Int` arithmetic for constant folding in `Compile`.
- `omega` for label and jump-offset arithmetic in `Compile` and `Cost`.

The main theorem is stated for closed terms first, then for terms whose free
variables lie in the environment domain:

    theorem compile_correct (e : Expr) (ρ : Env) (h : e.freeVars ⊆ ρ.domain) :
      (run (compile e) ⟨ρ, []⟩).map (fun s => s.stack) = some (eval e ρ :: [])

The exact statement is settled at F1, when Mathlib links for the first time. F0
runs both sides on ten samples and compares the results, which is evidence but
not a proof.

## Test tiers inside the machine

| Check | Rule | What it proves about the ruleset |
| --- | --- | --- |
| `lean_test` on `Lisp/Test/Eval.lean` | interpreter run | `--run`, `LEAN_PATH`, runfiles |
| `bazel build //lisp:Lisp` | `lean_library` | per-module actions, cache keys |
| `lean_axiom_test` on `Correctness` | axiom gate | the proof uses only `propext`, `Classical.choice`, `Quot.sound` |
| `bazel run //lisp:lisp -- prog.lisp` | `lean_binary` plus `data` | native link, runfiles data |
| edit `Lisp/Sexp.lean` | cache behaviour | only importers re-elaborate |
| `Lisp/Tools/Gen` | generated sources | a rule-generated `.lean` file compiles as a module |

## Milestones

Each milestone pairs a ruleset feature with a piece of the machine.

| # | Ruleset feature | Machine change | Acceptance |
| --- | --- | --- | --- |
| F0 | `lean_library`, `lean_test`, toolchain | `Expr`, `Eval`, `VM/Word`, `VM/Machine`, `Compile`, `Test/Eval` | done: `bazel test //lisp/...` passes 10 checks; a comment in a leaf module costs one action, a definition costs six |
| F1 | Mathlib oleans from the cache | `Env` on `Finsupp`, `Subst`, `Correctness` for `let` and `if` | done: the proof builds with zero Mathlib source builds |
| F2 | generated sources, `lean_binary` | `Tools/Gen` emits a program; `lisp` links natively | done: `bazel run //lisp:lisp -- prog.lisp` prints the machine result; `data` files reach runfiles |
| F3 | import-closure fetch | the proof imports few Mathlib modules | done: measured fetch size follows the imports, not all of Mathlib |
| F4 | `forbid_sorry`, `lean_axiom_test` | gates on `Correctness` | done: a planted `sorry` fails the build; the axiom list is printed |
| F5 | parallelism and cache at scale | a generated family of 800 programs | `--jobs` scaling and remote-cache hit ratio are reported |

## Rules for growth

1. A new Lean feature gets a machine module or a machine test before the
   ruleset documents the feature as supported.
2. The machine keeps compiling. A milestone removes no check.
3. Proofs stay small. Prefer a sharper statement over a longer proof.
4. `Eval` stays independent of the VM. If one side could satisfy the proof by
   calling the other, the test is worthless.
