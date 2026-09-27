# rules_lean

Bazel rules for [Lean 4](https://lean-lang.org/).

- Compile one Lean module per Bazel action. Do not run one `lake build`.
- Reuse prebuilt Mathlib oleans from the upstream cache. Fetch the import closure only.
- Pin the Lean toolchain with sha256. Do not call `elan` in a build.
- Fail a build on `sorry`. Check the axiom list of each theorem.

Status: pre-0.1.0. M0 works: `cd e2e/hello && bazel test //...` passes. The first
piece of the Lisp machine works: `bazel test //lisp/...` passes 10 checks.

## The problem

`lake build` is a single tool invocation over an entire package graph.

| Lake | Bazel (this ruleset) |
| --- | --- |
| one cache key for the whole build | action key per module |
| one process, internal parallelism | `--jobs` times sandboxed actions, remote-cacheable |
| Mathlib: about 5 GB of oleans, fetched whole | the import closure of your modules |
| toolchain from `~/.elan`, ambient | pinned tarball, sha256, per platform |
| cache on the local disk only | disk cache, remote cache, remote execution |

## Test suites

| Tier | What it is | Where |
| --- | --- | --- |
| Unit | one rule, one feature, seconds | `e2e/`, one bzlmod module per case |
| Shape | a project the size of a real one, in the repository | `examples/rtl`, the RTL demo |
| Math | theorems, with the proof technique and the axiom footprint of each | `proofs/` |
| Integration | a Lean project that grows with the ruleset | `lisp/`, the Lisp machine |
| Field | projects outside this repository that use the ruleset | not in this repository |

The Lisp machine is the long-term integration suite: a small Lisp with a
correctness proof against Mathlib, compiled to a stack machine. Each ruleset
feature gets a piece of it. See [docs/lisp-machine.md](docs/lisp-machine.md).

`examples/rtl` is a project of realistic shape, in this repository, so the
default build gates it. It has 10 files:

| Feature of a real project | In the demo |
| --- | --- |
| Nested namespaces | `Rtl.*`, `Isa.*`, `Codegen.Emit` |
| A generated source | `Isa/Opcodes.lean` from a `genrule`, compiled by `Isa.Decode` |
| Warnings as errors | `extra_flags = ["-DwarningAsError=true"]` on one library |
| A root module that imports everything | `Rtl.lean` |
| A project test | `//examples/rtl:rtl_test`, 9 checks |
| A native command line tool | `bazel run //examples/rtl:rtl_emit -- examples/rtl/Spec.txt` |
| A runfiles data file | `Spec.txt`, read by the tool at run time |

A demo with Mathlib, executables, and a test driver lands with M1.

`proofs/` is the mathematics tier. Lean core has no `Nat.Prime`, no `Finset`,
and no `norm_num`, so the tier builds its own number theory and keeps the
contrast visible. Each theorem states a technique, and each one reports its
axioms:

| Theorem | Technique | Axioms (`#print axioms`) |
| --- | --- | --- |
| `no_surjection_nat_bool` | Cantor diagonalization | `propext` |
| `no_sqrt2` | infinite descent, parity | `propext`, `Quot.sound` |
| `exists_prime_gt` | Euclid, minimal divisor | `propext`, `Classical.choice`, `Quot.sound` |
| `sumOdds_eq` | induction | `propext`, `Quot.sound` |

Eleven checks run the computational content. See
[docs/proofs.md](docs/proofs.md).

## Requirements from real projects

The ruleset serves projects that use Lean at scale. Each requirement below is a
rule feature with a test in this repository.

1. A module root that is not the repository root. The rule uses the Bazel
   package directory as the root, so a `BUILD.bazel` file in `lean/` gives
   `lean/Foo.lean` the module name `Foo`.
2. Generated `.lean` files as `srcs`.
3. `lean_binary` with a main module by name, as Lake's `root :=` does, so a
   project with many executables does not repeat file paths.
4. `extra_flags` and `extra_env` per target.
5. Runtime `data` for runfiles.
6. Cache-covered dependencies beyond Mathlib. The list `isPartOfMathlibCache` in
   mathlib4 `Cache/IO.lean` holds `Batteries`, `Aesop`, `Cli`, `ImportGraph`,
   `LeanSearchClient`, `Plausible`, `Qq`, `ProofWidgets`, and more, so a
   dependency of a Mathlib project can come from the cache with no source build.
7. Version entries for 4.34.x, including release candidates.

## Install

```starlark
# MODULE.bazel
bazel_dep(name = "rules_lean", version = "0.1.0")

lean = use_extension("@rules_lean//lean:extensions.bzl", "lean")

# The version comes from //:lean-toolchain, or from the version attribute.
lean.toolchain(toolchain_file = "//:lean-toolchain")

use_repo(lean, "lean_toolchains")
register_toolchains("@lean_toolchains//:all")
```

`use_repo` and `register_toolchains` complete the setup.

## Use

```starlark
# BUILD.bazel
load("@rules_lean//lean:defs.bzl", "lean_library", "lean_test", "lean_axiom_test")

lean_library(
    name = "arith",
    srcs = ["Arith.lean"],
)

lean_library(
    name = "proofs",
    srcs = ["Proofs.lean"],
    deps = [
        ":arith",
        "@mathlib//:Mathlib.Data.Finset.Basic",
    ],
)

lean_test(
    name = "proofs_test",
    srcs = ["Proofs.lean"],
    entry = "Proofs.lean",
    deps = [":arith"],
)

lean_axiom_test(
    name = "axioms_test",
    deps = [":proofs"],
    theorems = ["Proofs.card_empty"],
)
```

## Rules

| Rule | Produces | Notes |
| --- | --- | --- |
| `lean_library` | `.olean` per module | `srcs`, `deps`, `extra_flags`; one action per source |
| `lean_test` | a test | `srcs`, `entry`, `deps`; runs the entry with `lean --run` |
| `lean_prebuilt_library` | an importable olean tree | planned, M1 |
| `lean_binary` | a native executable | `main` names the module with `main`, as Lake's `root :=`; `data` reaches runfiles |
| `lean_axiom_test` | a test | planned, M4 |
| `lean_toolchain` | a toolchain | write it in a BUILD file for a local compiler |

The module name of a source is its path relative to the Bazel package
directory, as in Lake's `srcDir`. `lean/Foo.lean` in package `//lean` is
module `Foo`.

### Oleans and `LEAN_PATH`

Lean looks up an imported module `A.B` at `<LEAN_PATH entry>/A/B.olean`, and it
takes the *first* entry that holds the top-level directory `A`. It does not
continue to later entries. Test: with `d1/Lisp/Expr.olean` and
`d2/Lisp/Eval.olean`, `LEAN_PATH=d1:d2` fails on `import Lisp.Eval`, even though
`d2` holds the file.

The oleans of a package therefore land in one directory, the output directory of
the package, and that directory is the `LEAN_PATH` entry. Each file still comes
from its own action. An action declares the oleans it reads, so the directory
holds exactly the declared files.

### Import graph

`deps` gives the dep edges. The rule does not read `import` lines yet, so a
target that holds several modules cannot order them itself. Two ways to work
today: one target per module, or one target per dependency layer.

Reading the import graph needs a file read at analysis time. A Bazel rule cannot
read a source file (`ctx.read` does not exist on Bazel 9.2.0, test result), so
the scan belongs in a module extension or a repository rule. It is on the
roadmap, and the Lisp machine is its test.

## Architecture

```
lean-toolchain ───┐                      (version string, elan format)
lake-manifest.json┤                      (lockfile: workspace deps, pinned revs)
                  ▼
        ┌──────────────────────────────────────────────────┐
        │ @lean_toolchains  — release tarball, sha256       │
        │   bin/lean, lib/lean/libleanshared.so             │
        │   lib/lean/**                    (prebuilt oleans)│
        └──────────────────────────────────────────────────┘
        ┌──────────────────────────────────────────────────┐
        │ @mathlib — .ltar from cache.mathlib.org, leantar  │
        │   extracted to per-module targets                 │
        └──────────────────────────────────────────────────┘
   //P/A.lean ─lean─▶ A.olean ─┐
   //P/B.lean ─lean─▶ B.olean ─┴─▶ lean_test (interpreter) | lean_axiom_test

   lean_binary:  //P/A.lean ─lean -c─▶ A.c ─┐
                 //P/B.lean ─lean -c─▶ B.c ─┴─leanc─▶ executable
```

### Toolchain

A Lean toolchain is a release tarball from `leanprover/lean4`. A repository
rule downloads the tarball, verifies a sha256 from
`lean/private/known_lean_versions.bzl`, and declares a Bazel toolchain:

```
@lean_toolchains                hub repository, holds the toolchain targets
  :lean_4_34_1_linux_x86_64         -> @lean_toolchain_4_34_1_linux_x86_64
  :lean_4_34_1_darwin_aarch64       -> @lean_toolchain_4_34_1_darwin_aarch64
```

`register_toolchains("@lean_toolchains//:all")` registers every target. Bazel
filters them by platform constraint and picks the match for the host. Rules read
the toolchain through `toolchain_type @rules_lean//lean:toolchain_type`. No rule
runs `elan` and no rule reads `~/.elan`.

`lean_toolchain(...)` is also a public rule. Write it in a `BUILD.bazel` file to
use a Lean binary from another source, for example a patched compiler or a local
checkout.

Asset names and sums come from the GitHub release API:

    curl -sSL https://api.github.com/repos/leanprover/lean4/releases/tags/v4.34.1 \
      | grep -E '"(name|digest)"'

#### Where the version lives

Four candidates. All tests ran on Bazel 9.2.0.

| Candidate | Result |
| --- | --- |
| `load()` a constant in `MODULE.bazel` | Rejected: `` `load` statements may not be used in MODULE.bazel files ``. |
| `lean.toolchain(version = "4.34.1")` | Works. The version string then exists twice. |
| Read `//:lean-toolchain` in the extension | Works. A tag label resolves in your module, and a repository rule that the extension instantiates reads the file. The test returned `leanprover/lean4:v4.34.1`. |
| Download the tarball in a build action | Not possible: an action has no network. |

The version string lives in `lean-toolchain`. `MODULE.bazel` points at that
file. Two reasons:

1. It is the Lean convention. `elan`, `lake`, and the editor read `lean-toolchain`.
2. Mathlib hashes the content of that file into its olean cache key.

Guards:

- `toolchain_file` and `version` together must be equal, or the build stops.
- The file must equal the `lean-toolchain` of the pinned Mathlib revision.
  The Mathlib cache key hashes `lean-toolchain` and `Lean.githash`, so a
  mismatch yields oleans that the toolchain cannot load. Planned, M1.

`elan` remains usable for developer commands (`lake update`,
`lake exe cache get`, editor support). Its state (`ELAN_TOOLCHAIN`,
`elan override`, the default toolchain) never enters a build.

#### Action inputs

Lean opens five files per imported module: `.olean`, `.olean.private`,
`.olean.server`, `.ir`, `.ir.sig`. Measured with `strace` on 4.34.1. It does not
open `.ilean` during compilation. The generated repository declares a `stdlib`
filegroup from those patterns, plus `lib/lean/*.so*`, the shared library of the
compiler itself.

Cost, Lean 4.34.1, linux x86_64:

| Files | Size |
| --- | --- |
| `.olean.private` | 1298 MiB (2518 files) |
| `.ir` | 358 MiB (2518 files) |
| `.olean` | 340 MiB (2520 files) |
| `.ilean`, not an input | 83 MiB (2520 files) |
| `.olean.server` | 31 MiB (2518 files) |
| `lib/lean` total | 2.8 GB |

The action input set is 2.0 GB instead of 2.8 GB. Bazel hashes each file once
and reuses the digest, so the cost is a one-time hash plus the digest set per
action. A later milestone narrows the set to the modules a source imports.

#### The `-R` root

Lean derives a module name from the file path relative to `-R`, and it refuses a
file outside that root. It resolves the file path first
(`moduleNameOfFileName` in `Lean/Util/Path.lean`). A sandbox holds real
directories and symlinked files, so a root computed from the sandbox path does
not contain the resolved file. The rules derive the root at execution time from
the resolved file path. `_ROOT_SNIPPET` in `lean/private/lean_rules.bzl`.

An olean must sit at `<LEAN_PATH entry>/<module path>.olean`. Test: after a
module `b.C` is written to `<dir>/b/C.olean`, `import b.C` resolves. Oleans are
independent of the absolute path of the build: two builds of the same module in
two directories produce the same sha256.

### Lake

`lake-manifest.json` is the only source of dependency data. `rules_lean` reads it
as a lockfile.

| | |
| --- | --- |
| Parsed | `lake-manifest.json`: package name, git URL, pinned rev |
| Never | `lakefile.lean` evaluation, `lake` at build time, network from a build action |
| Convenience | `lakefile.toml` read for package metadata when no manifest exists |
| Dev-only | `lake update` to regenerate the manifest |

The ruleset builds the sources of your project in Bazel, one module per action.
It builds a workspace dependency in the same way, unless the upstream cache
covers that dependency (Mathlib, and the packages in `isPartOfMathlibCache`).
Then it uses prebuilt oleans.

### Mathlib

Mathlib publishes olean sets. Each set has a key: a hash over the git rev
content, `lean-toolchain`, `Lean.githash`, and the lakefile settings. The cache
serves the sets as `.ltar` containers (Lean tar, per-file compression) from
`https://cache.mathlib.org`. The URL form is `/{container}/{key}`. Containers:
`master`, `forks`, `nightly-testing`, `pr-toolchain-tests`. Extract the
containers with [`leantar`](https://github.com/digama0/leangz).

Design:

1. Fetch the import closure of your modules
   (`@mathlib//:Mathlib.Data.Finset.Basic`). Do not fetch all 6000 modules. The
   closure comes from the dependency map of the cache tool, or from our own
   fetcher at M3.
2. Generate one target per module. A source change then recompiles only the
   modules that import it, and the Bazel keys follow the import edges.
3. Add the aggregate target `@mathlib//:Mathlib` for `import Mathlib`.
4. Assume that oleans are platform-independent. The upstream cache serves one
   artifact set for all platforms. Verify this at M1. Code from `native_decide`
   goes into the linked binary, not into the olean.

The cold fetch uses the network. The Bazel repository cache holds the result.
Later builds are offline.

## Parallelism and cache efficiency

The ruleset keeps these invariants:

| Invariant | Reason |
| --- | --- |
| One action per module (`.lean` to `.olean`) | Bazel runs many actions in parallel. `lake` runs one process. |
| Action key: toolchain, flags, source, dep oleans | The key comes from Bazel. It is never a whole-package key. |
| Repo-relative paths | No absolute path enters the action key. Sandboxes on other machines hit the same cache entry. |
| Declared outputs only: the `.olean` | Test: `lean -o x.olean Foo.lean` writes one file. |
| One dep edge per import | A change in a leaf module re-elaborates only the modules that import it. |
| Split toolchain inputs | The action carries 2.0 GB of `lib/lean`, not 2.8 GB. |
| Network access in repository rules only | An action stays hermetic and fits remote execution. |
| `--remote_download_minimal` | Remote execution transfers only the files the next step reads. |

Measured on the M0 e2e (`e2e/hello`, two tests, three modules):

| Event | Actions |
| --- | --- |
| first build | 6 sandbox actions |
| rebuild, no change | 1 action: the test run. Olean actions cached. |
| edit one leaf module | 3 sandbox actions, 1 test re-run. The unrelated test stayed cached. |

Measured on the native pipeline (`//examples/rtl:rtl_emit`, a four-module
closure):

| Event | Actions |
| --- | --- |
| first build | 4 code-generation actions, 1 link |
| rebuild, no change | 0 compile actions |
| comment in a leaf module | 2 actions: the olean and the C of that module. The link hits the cache, because the C is identical. |

`lean_binary` links statically against the Lean runtime: the result is a 4.3 MB
ELF executable with no Lean library at run time. The link reads 544 MB of
toolchain inputs (`lib/lean/*.a` 384 MB, `lib/*.a` and `lib/*.so*` 156 MB, the
bundled clang and glibc).

The closure of a `lean_binary` is the dependency set, not the import graph,
because the rules do not read import lines yet. A binary over Mathlib would
generate C for 6000 modules. M0b fixes this.

Measured on the Lisp machine (`//lisp`, seven targets, seven modules, one test):

| Event | Actions |
| --- | --- |
| rebuild, no change | 0 actions. The test result is cached. |
| add a comment to a leaf module | 1 action. The olean is byte-identical, so Bazel skips the importers. |
| add a definition to a leaf module | 6 sandbox actions: the module, its four importers, and the test. |

A later option: one persistent worker holds the imported Mathlib environment for
several modules and lowers the import cost per action. Set
`--worker_max_instances` to the fan-out. Not in v0.

## Decisions

| # | Decision | Reason |
| --- | --- | --- |
| D1 | Hermetic toolchain from release tarballs; no `elan` at build time | The same tarball builds on every machine. |
| D2 | The version string lives in `lean-toolchain` | `load()` is rejected in `MODULE.bazel`. A second copy can disagree with the Mathlib cache key and with `lake`. |
| D3 | `lake-manifest.json` is the only dep source; never evaluate `lakefile.lean` | An evaluator needs a toolchain, and analysis cannot run Lean. A build action must not use the network. |
| D4 | Mathlib from prebuilt oleans, never from source | A source build of Mathlib needs hours and about 5 GB. |
| D5 | Import-closure fetch, not whole-cache fetch | Mathlib is about 5 GB. Most users need a fraction of it. |
| D6 | One prebuilt target per module, generated by a repository rule | The dep edges then match the imports, and the cache keys follow. |
| D7 | bzlmod only; Bazel 8 and 9 | Bazel 9 removed the native cc rules (test result), so `rules_cc` is a hard dependency. |
| D8 | Module name: path relative to the Bazel package directory | It matches Lake's `srcDir`, and it keeps the olean path equal to the module path. |
| D9 | Module name `rules_lean` | The name is free on the BCR (test result). `pulseengine/rules_lean` and `tomato-bazel/rules_lean` use it on GitHub. Publish early to hold the name. |

## Non-goals

- Reimplementing the Lake resolver or `lake build`. `lake update` produces a manifest.
- Lean 3.
- A Lean IDE or LSP server. `.ilean` is emitted when a user asks for it.
- Windows in 0.1.0. Lean and `leanc` on MSVC need separate work. Linux and macOS
  on x86_64 and aarch64 are in scope.

## Platforms and versions

| | 0.1.0 |
| --- | --- |
| Bazel | 8.x, 9.x, bzlmod only |
| Lean | tagged releases with a sha256 in the table; 4.29.1, 4.32.2, 4.34.0-rc1, 4.34.1 |
| Linux x86_64, aarch64 | supported |
| macOS x86_64, aarch64 | supported |
| Windows | not supported |

## Roadmap

Ruleset milestones carry the machine milestones of
[docs/lisp-machine.md](docs/lisp-machine.md).

| Milestone | Deliverable | Acceptance |
| --- | --- | --- |
| M0 | toolchain repository rule, `lean_library`, `lean_test`, hello e2e | done: `bazel test //e2e/hello/...` passes; rebuild is a no-op; one leaf edit recompiles its importers only |
| M0b | import-graph scan in a module extension | a multi-module target gets exact per-module edges and full parallelism; the Lisp machine collapses to one target |
| M1 | Mathlib oleans from the cache, `lean_prebuilt_library` | the Lisp proof of F1 compiles with zero Mathlib source builds; offline after the first fetch; the `proofs/` tier gains Mathlib versions that replace the hand-rolled lemmas |
| M2 | `lake-manifest.json` to per-dep repositories | a project with two git deps builds with per-module actions, and no `lake` at build time |
| M2b | done: `lean_binary` | `bazel run //examples/rtl:rtl_emit -- examples/rtl/Spec.txt` prints `block inputs=3`; the executable is 4.3 MB and links no Lean shared library |
| M3 | import-closure fetch, own fetcher, no `lake` binary | fetch size follows the imports |
| M4 | `forbid_sorry`, `lean_axiom_test`, negative tests | each gate fails on a planted `sorry` or `native_decide` |
| M5 | BCR: `0.1.0` tag, `.bcr/{metadata,source,presubmit}`, pull request | `bazel_dep(name = "rules_lean")` installs from the BCR |

## Layout

```
MODULE.bazel
lean/            defs.bzl, extensions.bzl, toolchain.bzl
lean/private/    toolchain repository rules, versions table, compile rules
lake/            manifest parsing, dep repositories, dev helpers
mathlib/         cache client, ltar fetch, target generation
lisp/            the Lisp machine, the long-term test suite
e2e/             one bzlmod module per scenario, run by BCR presubmit
docs/            design documents
tools/           release and registry helpers
```

## Publishing

Scaffolded from [`bazel-contrib/rules-template`](https://github.com/bazel-contrib/rules-template):
a tag push builds the release artifact, and `.bcr/source.json` records the
archive URL and its integrity value. A pull request then adds the module to
`bazelbuild/bazel-central-registry`.

BCR requirements: `metadata.json` with maintainers, a license, a presubmit
matrix, and an `e2e/` module that exercises the rules.

BCR policy discourages generic `rules_*` names unless the ruleset is the
community standard for that language. Publish 0.1.0 after M1 to hold the name.

## Open questions

1. Require a committed `lake-manifest.json`, or also accept a `lakefile.toml`-only
   project as a first-class input?
2. Toolchain distribution: fetch Lean release tarballs per user, or publish
   `lean_toolchains_*` repositories to the BCR, rules_rust style?
3. Ship our own `cache`/`leantar` binary as a ruleset toolchain, or depend on the
   upstream `leantar` release binaries?
4. Does Bazel fetch the repository of every registered platform toolchain, or
   only the host platform? M0 measured one platform so far.
5. Import graph: read `import` lines in a module extension that watches the
   sources, and pass the edges as a generated `.bzl` file that a BUILD file
   loads. The alternative is a source scan inside each rule, which Bazel does
   not allow.
