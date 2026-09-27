# Reproducing the upstream Lean test suite

The BCR argument for this ruleset is not "it builds my project". It is: the
ruleset builds and checks what the Lean compiler repository builds and checks.

The Lean repository (`leanprover/lean4`) tests the compiler with a pile of
`.lean` files, driven by CMake and per-directory `run_test.sh` scripts. This
document fixes the target: reproduce those piles with Bazel rules, at the same
tag as the toolchain, and report the same pass and fail counts.

## Fidelity

For every test file, the same command runs, the same artifact is compared, and
the same verdict is produced. Where a pile cannot be reproduced, this document
names it with the reason, and the CI report prints it as skipped rather than
silently.

| Pile | Files | Upstream check | Stage 1 |
| --- | --- | --- | --- |
| `tests/elab` | 3133 | the file elaborates; message assertions are `#guard_msgs` inside the file | 3125 build. 8 files are excluded, with the reason for each. |
| `tests/compile` | 71 | `lean --c` then `leanc`, then run the program and compare stdout with `.out.expected` | 71 elaborate and link. The stdout comparison is stage 2. |
| `tests/elab_fail` | 315 | elaboration must fail, and the messages must match `.out.expected` | not generated: stage 3 |
| `tests/docparse` | 202 | `lean --run run_test.lean <file.txt>`, then compare | not generated: stage 2 |
| `tests/misc` | 5 | the `lean` command line exits with the expected status | not generated: stage 2 |
| `tests/server` | 4 | LSP protocol responses | no: tests the language server, not the compiler |
| `tests/lake` | 271 | Lake behaviour | no: tests Lake |
| `tests/pkg` | 211 | Lake package resolution | no: tests Lake |
| `tests/bench` (+ `*_bench`) | 47 | timings | no: measures speed, does not check a result |
| `tests/lean/grind` | 13 | none | no: the README calls them aspirational cases, expected to fail |
| `tests/lean/sym` | 2 | none | no: scratch files, no driver, no registration |
| `tests/ir` | 1 | none | no: the harness imports `init.Lean.Ir.lirc`, which no longer exists |
| `doc/examples/compiler` | 1 | `leanmake` | no: drives another build tool |

The excluded files of `tests/elab`, and why:

| Files | Reason |
| --- | --- |
| `async_select_channel.lean`, `sync_mutex.lean` | the upstream CMake excludes them from the pile |
| `Reformat.lean`, `parsePrelude.lean`, `readDir.lean` | read a path relative to the working directory, so they need fixture inputs and the driver's working directory |
| `importStructure.lean` | runs `lean` as a subprocess |
| `async_systems_info.lean` | spawns a process, which the sandbox refuses |

`nat_size_limit.lean` built once the generator read its `.init.sh` and passed
`LEAN_NAT_MAX_SIZE=16` through the `extra_env` attribute of `lean_library`. That
is the upstream convention: a test's environment comes from its `.init.sh` file.
The remaining four need the working directory and fixture inputs, or a
subprocess, which is stage 2 work on the rule.

Those six are the test driver, not the compiler: a working directory, fixture
inputs, environment variables, and a subprocess. Stage 2 adds them as rule
attributes. The distinction matters for the BCR report: the ruleset elaborates
every file of the pile that does not need the driver.

Counts come from the pinned archive:

    tar tzf lean4-4.34.1.tar.gz | grep -cE '^lean4-4\.34\.1/tests/elab/.*\.lean$'

## Mechanism

```
leanprover/lean4 @ v4.34.1
  https://github.com/leanprover/lean4/archive/refs/tags/v4.34.1.tar.gz
  sha256 9bb0bed7bae752a281e9923163d50da4193e36480cf5f639658e2e1502294056
        │
        │  @lean_samples  repository rule
        │    1. download and unpack the archive
        │    2. scan every .lean file for `import` lines
        │    3. map module name to file, and write one BUILD.bazel per pile
        ▼
  @lean_samples//elab/10067.lean.olean  (one action per file, edges from the scan)
  @lean_samples//compile/append         (native executable, linked by leanc)
```

The scan lives in a repository rule because a Bazel rule cannot read a source
file at analysis time (`ctx.read` does not exist on Bazel 9.2.0, test result).
The generated repository is also the prototype of the import graph of M0b: the
generated `deps` are the exact edges, so the suite builds with one action per
file and full parallelism.

Target names come from the file stem, with dots replaced by underscores:
`tests/elab/10067.lean` becomes `@lean_samples//elab:10067`. Each pile also gets
a `suite` filegroup, so CI can build one pile at a time.

## What the suite proves about the ruleset

| Claim | Pile that falsifies it |
| --- | --- |
| The toolchain, the loader inputs, and `LEAN_PATH` are complete | `tests/elab` (3133 files, every kind of import) |
| Per-file actions scale | all piles |
| Olean paths and module names match Lean's own convention | all piles |
| `lean_binary` links real programs | `tests/compile` |
| The action cache holds at scale | a second CI run rebuilds nothing |
| `#guard_msgs` message assertions run | `tests/elab` |

## CI

`.github/workflows/ci.yaml` has one job per concern:

| Job | Command | Checks |
| --- | --- | --- |
| `test` | `bazel test //...` in the root module | the ruleset, the demos, the proofs |
| `e2e` | `bazel test //...` in `e2e/hello` | the user-facing install path |
| `upstream` | `bazel build @lean_samples//...` in `e2e/upstream` | the compiler piles |
| `upstream-test` | `bazel test @lean_samples//...` | the piles that compare output (stage 2 onward) |

The `upstream` job prints a count of built targets and the failures, so a
regression names the pile and the file.

## Stages

| Stage | Deliverable | Acceptance |
| --- | --- | --- |
| 1 | done: fetch, scan, generate, elaborate `tests/elab`; link `tests/compile` | `bazel build @lean_samples//tests:pile_elab @lean_samples//tests:pile_compile` is green: 3126 elab files and 71 native programs, 3197 targets, 7 files excluded with a reason each |
| 2 | the test driver: run an action with the pile directory as its working directory, declare the fixture files of a test as inputs, and compare stdout and stderr against `.out.expected` | the four excluded files build; `tests/compile` and `tests/docparse` compare output; the fail list matches upstream's own list |
| 3 | `tests/elab_fail`: inverted verdict plus message comparison | a planted wrong message fails the test |
| 4 | the CI job reports per-pile counts into the run summary | the summary matches the inventory table |

## Stage 2 in detail

Three pieces, in the order they unblock tests.

1. **Fixture inputs.** `lean_library` gains a `data` attribute, which joins the
   action inputs. The generator declares the sibling paths a test reads:
   `readDir.lean.dir/` for `readDir.lean`, and the file `parsePrelude.lean`
   reads. Nothing else changes, because a declared input is a sandbox entry.
2. **Working directory.** The compile action changes into the directory of the
   source before it runs `lean`, which is what the upstream driver does
   (`WORKING_DIRECTORY "${DIR}"`). Two details: the output path becomes
   absolute, and every `LEAN_PATH` entry does too, because the entries are
   relative to the execution root. Both are shell work in `_ROOT_SNIPPET`, and
   both stay out of the action key, so the cache still hits across machines.
3. **Output comparison.** A rule that runs a step, captures stdout and stderr
   together, and compares against `<file>.out.expected`. Upstream's comparison
   is `diff -au --strip-trailing-cr` after three normalizations (metavariable
   suffixes, reference URLs, measurements). The rule takes the normalizations
   as a mode, so `tests/elab`, `tests/compile`, and `tests/docparse` share it.
   `tests/elab_fail` sets the same rule to expect a non-zero exit.

## Known unknowns

1. Upstream's driver sets flags and environment variables per pile
   (`tests/util.sh`, `run_test.sh`). The scan reproduces the *file* set; the
   flags are read from those scripts before stage 2, and any flag that changes
   elaboration becomes an `extra_flags` entry of the generated target.
2. Some piles contain files that are not standalone modules: a fragment that
   imports a sibling, or a file with a deliberate error. Stage 1 reports them
   and the generator can mark them `excluded` with a reason in the generated
   BUILD file.
3. The GitHub tag archive hash is pinned, and GitHub does not guarantee archive
   hashes forever. If the download fails the integrity check, the pin is
   refreshed deliberately, in one commit, with the new hash in this document.
