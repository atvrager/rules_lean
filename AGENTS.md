# AGENTS.md

Rules for work in this repository. They apply to code, comments, docs, and
replies.

## Prose

Write Simplified Technical English (ASD-STE100 style).

- One idea per sentence. Short common words. Active voice.
- State the fact, the number, the file, the command. Then stop.
- Delete any sentence that explains why the finding is interesting. The reader
  decides that.
- Do not announce what you are about to say. Say it.
- Do not narrate your own diligence or honesty. Report the correction as a fact
  about the code.
- No hype, no praise, no metaphor, no self-assessment.
- No emoji in technical prose.

Wrong: "**Key finding**: the toolchain ships IR files, which is why the build
stayed broken."

Right: "The toolchain ships `.ir` files (2 files, 1.2 MiB). The action did not
declare them, so Lean reported missing executable code."

## Lean and Bazel facts that shape the rules

- Lean derives a module name from the file path relative to a root (`-R`), and
  refuses a file outside that root. It resolves the file path first, so a
  sandbox symlink moves the file out of a sandbox-relative root. Derive the root
  at execution time from the resolved file path (`_ROOT_SNIPPET` in
  `lean/private/lean_rules.bzl`).
- An olean must sit at `<LEAN_PATH entry>/<module path>.olean`. `lean_library`
  mirrors the module path under `<target>.olean/` for this reason.
- A module name is the source path relative to the Bazel package directory. Put
  the `BUILD.bazel` file in the Lean source root.
- `LEAN_PATH` replaces the built-in search path. Always add the toolchain
  standard library directory explicitly.
- The toolchain loader opens `.olean`, `.olean.private`, `.olean.server`, and
  `.ir`, plus `.ir.sig`. All of them must be action inputs.
- Lean resolves an import by the *first* `LEAN_PATH` entry that holds the module's
  top-level directory, and it does not look at later entries. Test: with
  `d1/Lisp/Expr.olean` and `d2/Lisp/Eval.olean`, `LEAN_PATH=d1:d2` fails on
  `import Lisp.Eval`. The oleans of a package therefore go into one directory,
  the output directory of the package.
- A native program needs the C code of *every* module it imports: the generated
  C calls the initializer of each import, and the linker fails on
  `undefined symbol: initialize_<Module>` without it. `lean_binary` therefore runs
  one code-generation action per module in the dependency closure.
- `leanc` is clang with baked-in flags. It does not accept a `.lean` file:
  `lean -c X.c -o X.olean src.lean` first, then `leanc -o exe X.c ...`. The link
  is static against the Lean runtime, so a 4.3 MB binary needs no Lean shared
  library at run time.
- Network access belongs in repository rules. Actions stay hermetic.

- A native program links statically against the Lean runtime, so a runfiles
  tree needs the `data` files only.
- A source of another repository has a `../<repo>/` prefix in its `short_path`.
  Strip it before the package-directory comparison, or the module name is
  wrong.

## Commands

    bazel test //...                              # the rules, the demos, the proofs
    cd e2e/hello    && bazel test //...           # the install path
    cd e2e/upstream && bazel build @lean_samples//tests:pile_elab
    bazel run //:buildifier                       # format all BUILD and .bzl files


Run the first two after any change to `lean/`, and report the result. A change
to a rule is not finished until both pass.

## Repository layout

    lean/            the rules and the toolchain
    lisp/            the integration suite
    proofs/          the mathematics tier
    examples/rtl     a project-shaped demo
    examples/scheme  a project in the shape of an interpreter
    e2e/hello        the install path, and the BCR presubmit module
    e2e/upstream     the compiler test piles of leanprover/lean4
    docs/            design documents, one per tier

## Commits

Follow the commit rules of the global AGENTS.md. Commit each logical unit.
