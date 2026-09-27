# rules_lean

Bazel rules for [Lean 4](https://lean-lang.org/).

- Compile one Lean module per Bazel action. Do not run one `lake build`.
- Reuse prebuilt Mathlib oleans from the upstream cache. Fetch the import closure only.
- Pin the Lean toolchain with sha256. Do not call `elan` in a build.
- Fail a build on `sorry`. Check the axiom list of each theorem.

Status: pre-0.1.0. Nothing builds yet. This README is the design.

## The problem

`lake build` is a single tool invocation over an entire package graph:

| Lake | Bazel (this ruleset) |
| --- | --- |
| one cache key for the whole build | action key per module |
| one process, internal parallelism | `--jobs` × sandboxed actions, remote-cacheable |
| Mathlib = ~5 GB of oleans to self-host or fetch whole | only the import closure of your modules |
| toolchain from `~/.elan`, ambient | pinned tarball, sha256, per-platform |
| cache sits on disk, local only | disk cache + remote cache + remote execution |

## Install

```starlark
# MODULE.bazel
bazel_dep(name = "rules_lean", version = "0.1.0")

lean = use_extension("@rules_lean//lean:extensions.bzl", "lean")

# Lean version: read from your //:lean-toolchain, or pin explicitly.
lean.toolchain(toolchain_file = "//:lean-toolchain")

# Mathlib oleans, content-addressed by (mathlib rev, toolchain), fetched on demand.
lean.mathlib(rev = "v4.29.1")

use_repo(lean, "lean_toolchains", "mathlib")
register_toolchains("@lean_toolchains//:all")
```

`lean-toolchain` carries the version of your Lake workspace. Bazel and `lake`
then use the same version. `use_repo` and `register_toolchains` complete the setup.

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
    library = ":proofs",
    entry = "Proofs.lean",
)

lean_axiom_test(
    name = "axioms_test",
    library = ":proofs",
    theorems = ["Proofs.card_empty"],
)
```

## Rules

| Rule | Produces | Notes |
| --- | --- | --- |
| `lean_library` | `.olean` per module | import edges inferred, one action per `srcs` entry |
| `lean_prebuilt_library` | importable olean tree | wraps upstream/generated olean sets |
| `lean_binary` | native executable | `lean -c` → `leanc` link, `@[extern]` FFI via `cc_deps` |
| `lean_test` | test | elaborates, then runs `main`/`#eval` entry |
| `lean_axiom_test` | test | transitive axiom deps ⊆ `allowed_axioms` |
| `lean_emit` | `.c` / `.bc` / `.ll` | for AOT pipelines and audits |
| attribute `forbid_sorry` | — | default `True`; `sorryAx` anywhere in `srcs` fails the action |

The default axiom list holds Lean's three standard axioms
(`propext`, `Classical.choice`, `Quot.sound`). `sorryAx` and `Lean.ofReduceBool`
are not in the default list.

## Architecture

```
lean-toolchain ───┐                      (version string, elan format)
lake-manifest.json┤                      (lockfile: ws deps, pinned revs)
                  ▼
        ┌──────────────────────────────────────────────────┐
        │ @lean_toolchains  — release tarball, sha256       │
        │   bin/lean, bin/leanc, lib/libleanshared.so       │
        │   lib/lean/{Init,Std,Lean,Lake}.olean  (prebuilt) │
        └──────────────────────────────────────────────────┘
        ┌──────────────────────────────────────────────────┐
        │ @mathlib — .ltar from cache.mathlib.org, leantar  │
        │   extracted to per-module targets                 │
        └──────────────────────────────────────────────────┘
   //P/A.lean ─lean─▶ A.olean ─┐
   //P/B.lean ─lean─▶ B.olean ─┴─▶ lean_test | leanc ─▶ binary | lean_axiom_test
```

### Toolchain

`lean.toolchain()` accepts a `toolchain_file` label (the root module's
`lean-toolchain`, in elan format: `leanprover/lean4:v4.29.1`, `...:stable`,
`...:nightly-2026-01-01`) or an explicit `version`. The version selects a
per-platform tarball from the `leanprover/lean4` releases. A sha256 in
`lean/private/known_lean_versions.bzl` verifies the tarball.

- An unknown version stops the build. The user must then pass `sha256 = {...}`
  for each platform. The ruleset never downloads an unverified file.
- The tarball contains prebuilt oleans for `Init`/`Std`/`Lean`/`Lake`. The build
  never compiles the standard library.
- Layout of v4.29.1, linux x86_64: 2.7 GB total, 2.5 GB of it `lib/lean`. The
  toolchain repo splits into a **driver** (bin, shared libraries) and a
  **stdlib olean tree**. An action and its remote-cache digest then carry only
  the part they use.

### Lake

`lake-manifest.json` is the only source of dependency data. `rules_lean` reads it
as a lockfile.

| | |
| --- | --- |
| Parsed | `lake-manifest.json`: package name, git URL, pinned rev |
| Never | `lakefile.lean` evaluation (arbitrary Lean at analysis time), `lake` at build time, network from a build action |
| Convenience | `lakefile.toml` read for package metadata when no manifest exists |
| Dev-only | `lake update` to (re)generate the manifest; `elan` may be used here |

The ruleset builds the sources of your project in Bazel, one module per action.
It builds a workspace dependency in the same way, unless the upstream cache
covers that dependency (Mathlib). Then it uses prebuilt oleans.

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
   artifact set for all platforms. Verify this at M0. Code from `native_decide`
   goes into the linked binary, not into the olean.

The cold fetch uses the network. The Bazel repository cache holds the result.
Later builds are offline.

## Parallelism and cache efficiency

The ruleset keeps these invariants:

| Invariant | Reason |
| --- | --- |
| One action per module (`.lean` → `.olean`) | Bazel runs many actions in parallel. `lake` runs one process. |
| Action key = toolchain + flags + source + dep oleans | The key comes from Bazel. It is never a "whole package" key. |
| `--root` and repo-relative paths only | No absolute path enters the action key or an olean. Sandboxes on other machines then hit the same cache entry. |
| Declared outputs only: `.olean`, plus `.ilean` or `.c` on request | Test result: `lean -o x.olean Foo.lean` writes one file. |
| One dep edge per import | A change in a leaf module re-elaborates only the modules that import it. |
| Split toolchain inputs | The 2.5 GB `lib/lean` tree does not enter every action digest. |
| Network access in repository rules only | An action stays hermetic and needs no egress for remote execution. |
| `--remote_download_minimal` (`--remote_download_regex='.*\.olean'` for a local link) | Remote execution transfers only the files that the next step reads. |

Risk to settle at M0: do Lean oleans record the source path? Test: build the
same module in two sandbox roots and compare the oleans byte for byte. If the
paths differ, normalize them or document the limit.

A later option: one persistent worker holds the imported `Mathlib` environment
for several modules and lowers the import cost per action. Set
`--worker_max_instances` to the fan-out. Not in v0.

## Decisions

| # | Decision | Reason |
| --- | --- | --- |
| D1 | Hermetic toolchain from release tarballs; no `elan` at build time | The same tarball builds on every machine. `elan` stays a developer tool. |
| D2 | One version source, `//:lean-toolchain` | Bazel and `lake` cannot disagree. |
| D3 | `lake-manifest.json` is the only dep source; never evaluate `lakefile.lean` | An evaluator needs a toolchain, and analysis cannot run Lean. A build action must not use the network. |
| D4 | Mathlib from prebuilt oleans, never from source | A source build of Mathlib needs hours and ~5 GB. |
| D5 | Import-closure fetch, not whole-cache fetch | Mathlib is ~5 GB. Most users need a fraction of it. |
| D6 | One prebuilt target per module, generated by a repository rule | The dep edges then match the imports, and the cache keys follow. |
| D7 | bzlmod only; Bazel 8 and 9 | Bazel 9 removed the native cc rules (test result), so `rules_cc` is a hard dependency. |
| D8 | Module name `rules_lean` | The name is free on the BCR (test result). `pulseengine/rules_lean` and `tomato-bazel/rules_lean` use it on GitHub. Publish early to hold the name. |

## Non-goals

- Reimplementing Lake's resolver or `lake build`. `lake update` stays the way to
  produce a manifest.
- Lean 3.
- Being a general Lean IDE/LSP server. `.ilean` is emitted because Lean emits it.
- Windows in 0.1.0. Lean and `leanc` on MSVC need separate work. Linux and macOS
  on x86_64 and aarch64 are in scope for 0.1.0.

## Platforms & versions

| | 0.1.0 |
| --- | --- |
| Bazel | 8.x, 9.x (bzlmod only) |
| Lean | any tagged release with a pinned sha256; 4.29.1 and 4.32.2 exercised |
| Linux x86_64/aarch64 | supported |
| macOS x86_64/aarch64 | supported |
| Windows | unsupported |

## Roadmap

| Milestone | Deliverable | Acceptance |
| --- | --- | --- |
| M0 | toolchain repo rule + `lean_library`/`lean_test` + hello-world e2e | `bazel test //e2e/hello` green; rebuild is a no-op; olean path-independence measured |
| M1 | Mathlib prebuilt oleans, whole-cache fetch first | `import Mathlib.Data.Finset.Basic` type-checks with zero Mathlib compilation; offline after first fetch |
| M2 | `lake-manifest.json` → per-dep repos; fine-grained source builds for non-Mathlib deps | a project with two git deps builds with per-module actions |
| M3 | Import-closure subset fetch; own fetcher (no `lake` binary, no `cache` exe) | fetch size proportional to imports; hashmap computed in-rule |
| M4 | `forbid_sorry` + `lean_axiom_test` gates, with negative tests | each gate fails on a planted `sorry`/`native_decide` |
| M5 | BCR: `0.1.0` tag, `.bcr/{metadata,source,presubmit}`, publish PR | module installable via `bazel_dep(name = "rules_lean")` from the BCR |

## Layout

```
MODULE.bazel
lean/            defs.bzl, extensions.bzl, toolchain.bzl
lean/private/    toolchain repo rule, versions db, compile actions
lake/            manifest parsing, dep repos, dev helpers
mathlib/         cache client, ltar fetch, target generation
e2e/             one bzlmod module per scenario, run by BCR presubmit
examples/        hello, mathlib, multi-module
tools/           release + registry helpers
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

1. Persist `lakefile.toml`-only projects (no manifest) as a first-class input, or
   require a committed `lake-manifest.json` like every other Bazel ecosystem?
2. Toolchain distribution: fetch Lean release tarballs per user, or publish
   `lean_toolchains_*` repos to the BCR (rules_rust style) so versions are shared?
3. Ship our own `cache`/`leantar` binary as a ruleset toolchain, or depend on
   upstream `leantar` release binaries?
