"""The `lean_library` and `lean_test` rules.

Model
-----

Lean derives the module name of a file from the file path relative to the
package root (`-R`), and it looks up an imported module `A.B` as
`<LEAN_PATH entry>/A/B.olean`. Two consequences:

* One `.lean` file is one Bazel action and one `.olean` output. Actions run in
  parallel, and a change in one module re-elaborates only its importers.
* The module name of a source is its path relative to the Bazel package
  directory. A `BUILD.bazel` file in `lean/` therefore gives `lean/Foo.lean` the
  module name `Foo`.

Lean resolves an import by the *first* `LEAN_PATH` entry that holds the module's
top-level directory, and it does not continue to later entries. Two entries
`d1/Lisp/Expr.olean` and `d2/Lisp/Eval.olean` do not make `import Lisp.Eval`
resolve when `d1` comes first. The oleans of a package therefore go into one
directory, the output directory of the package, and that directory is the
`LEAN_PATH` entry. A consuming action declares the oleans it needs, so the
directory holds exactly those files.
"""

load("//lean:toolchain.bzl", "TOOLCHAIN_TYPE")

LeanLibraryInfo = provider(
    doc = "Oleans of one `lean_library`, and the directories that hold them.",
    fields = {
        "olean_dirs": "depset[str]: `LEAN_PATH` entries for actions, transitive.",
        "module_sources": "depset[tuple[str, str, File]]: module path, module name, " +
                          "and source file, transitive.",
        "oleans": "depset[File]: oleans, transitive.",
        "runfiles_olean_dirs": "depset[str]: `LEAN_PATH` entries for runfiles, transitive.",
    },
)

_LEAN_BIN = "bin/lean"
_STDLIB_DIR = "lib/lean"
_OLEAN_SUFFIX = ".olean"

def _module_rel(ctx, src):
    """Return the module path of a source: "Foo/Bar" for "Foo/Bar.lean".

    Generated files carry the output directory in `short_path`; source files do
    not. In both cases the module path is the remainder after the package
    directory.
    """
    rel = src.short_path
    bin_prefix = ctx.bin_dir.path + "/"

    if rel.startswith(bin_prefix):
        rel = rel[len(bin_prefix):]

    package = ctx.label.package
    if package:
        if not rel.startswith(package + "/"):
            fail("%s: %s is outside package %s. Declare it in a lean_library in " +
                 "its own package." % (ctx.label, src.short_path, package))
        rel = rel[len(package) + 1:]

    if not rel.endswith(".lean"):
        fail("%s: %s is not a .lean file" % (ctx.label, src.short_path))
    return rel[:-len(".lean")]

def _dir_of(path, suffix):
    """Strip a known suffix from a path, leaving the directory."""
    if not path.endswith(suffix):
        fail("path '%s' does not end with '%s'" % (path, suffix))
    return path[:-len(suffix)]

def _parent_of(path, child):
    """The directory that holds `child`, as "." when that is the root."""
    if path == child:
        return "."
    return _dir_of(path, "/" + child)

# Lean derives the module name of a file from its path relative to a root, and
# it refuses a file outside that root. It resolves the file path first, and
# Bazel inputs are symlinks, so derive the root from the resolved path.
# Requires: $LEAN_SRC, $LEAN_MODREL. Sets $root.
_ROOT_SNIPPET = """# Resolve the file's own symlinks: a sandbox creates real directories and
# symlinks the files, and Lean resolves the file but not the root.
canon="$LEAN_SRC"
while [ -L "$canon" ]; do
  link="$(readlink -- "$canon")"
  case "$link" in
    /*) canon="$link" ;;
    *) canon="$(dirname -- "$canon")/$link" ;;
  esac
done
canon="$(cd -- "$(dirname -- "$canon")" && pwd -P)/$(basename -- "$canon")"
case "$canon" in
  */"$LEAN_MODREL.lean") root="${canon%/"$LEAN_MODREL.lean"}" ;;
  *)
    echo "rules_lean: cannot derive the Lean root of '$LEAN_SRC';" \\
         "expected a path that ends in '$LEAN_MODREL.lean'" >&2
    exit 1
    ;;
esac
"""

def _stdlib_dir(tc, attribute):
    """The standard library directory, as an execution path or runfiles path."""
    return _dir_of(getattr(tc.lean, attribute), _LEAN_BIN) + _STDLIB_DIR

def _transitive(deps, field):
    return depset(transitive = [getattr(dep[LeanLibraryInfo], field) for dep in deps])

def _compile_modules(ctx, tc, srcs, deps, extra_flags):
    """Compile one action per source. Returns the oleans and their directory."""
    dep_oleans = _transitive(deps, "oleans")

    # Lean searches LEAN_PATH in order and replaces its built-in path, so the
    # standard library must be an explicit entry.
    lean_path = ":".join(_transitive(deps, "olean_dirs").to_list() + [_stdlib_dir(tc, "path")])

    olean_dir = None
    runfiles_olean_dir = None
    oleans = []
    for src in srcs:
        module_rel = _module_rel(ctx, src)
        out = ctx.actions.declare_file("%s%s" % (module_rel, _OLEAN_SUFFIX))

        if olean_dir == None:
            olean_dir = _parent_of(out.path, "%s%s" % (module_rel, _OLEAN_SUFFIX))
            runfiles_olean_dir = _parent_of(out.short_path, "%s%s" % (module_rel, _OLEAN_SUFFIX))

        ctx.actions.run_shell(
            command = "set -euo pipefail\n\n" + _ROOT_SNIPPET + """
exec "{lean}" -o "$LEAN_OUT" -R "$root" "$LEAN_SRC" "$@"
""".format(lean = tc.lean.path),
            arguments = extra_flags,
            inputs = depset(
                direct = [src],
                transitive = [tc.stdlib, dep_oleans],
            ),
            outputs = [out],
            tools = [tc.lean],
            env = {
                "LEAN_PATH": lean_path,
                "LEAN_OUT": out.path,
                "LEAN_SRC": src.path,
                "LEAN_MODREL": module_rel,
            },
            mnemonic = "LeanOlean",
            progress_message = "Lean %s" % module_rel,
        )
        oleans.append(out)

    return struct(
        module_sources = [
            (_module_rel(ctx, src), _module_rel(ctx, src).replace("/", "."), src)
            for src in srcs
        ],
        olean_dir = olean_dir,
        oleans = depset(direct = oleans, transitive = [dep_oleans]),
        runfiles_olean_dir = runfiles_olean_dir,
    )

def _lean_library_impl(ctx):
    tc = ctx.toolchains[TOOLCHAIN_TYPE].lean_toolchain
    result = _compile_modules(ctx, tc, ctx.files.srcs, ctx.attr.deps, ctx.attr.extra_flags)

    return [
        DefaultInfo(files = result.oleans),
        LeanLibraryInfo(
            olean_dirs = depset(
                direct = [result.olean_dir],
                transitive = [_transitive(ctx.attr.deps, "olean_dirs")],
            ),
            module_sources = depset(
                direct = result.module_sources,
                transitive = [_transitive(ctx.attr.deps, "module_sources")],
            ),
            oleans = result.oleans,
            runfiles_olean_dirs = depset(
                direct = [result.runfiles_olean_dir],
                transitive = [_transitive(ctx.attr.deps, "runfiles_olean_dirs")],
            ),
        ),
    ]

lean_library = rule(
    implementation = _lean_library_impl,
    attrs = {
        "deps": attr.label_list(
            providers = [LeanLibraryInfo],
            doc = "Lean libraries that these sources import.",
        ),
        "extra_flags": attr.string_list(
            doc = "Extra flags for `lean`, for example [\"-DwarningAsError=true\"].",
        ),
        "srcs": attr.label_list(
            allow_files = [".lean"],
            mandatory = True,
            doc = "Lean sources. Each file becomes one `.olean`.",
        ),
    },
    toolchains = [TOOLCHAIN_TYPE],
    doc = "Compiles Lean sources to oleans, one action per source.",
)

def _lean_test_impl(ctx):
    tc = ctx.toolchains[TOOLCHAIN_TYPE].lean_toolchain
    result = _compile_modules(ctx, tc, ctx.files.srcs, ctx.attr.deps, ctx.attr.extra_flags)

    entry = ctx.file.entry
    if entry not in ctx.files.srcs:
        fail("%s: entry %s is not in srcs" % (ctx.label, entry.short_path))

    dep_infos = [dep[LeanLibraryInfo] for dep in ctx.attr.deps]
    lean_path = ":".join(
        _transitive(ctx.attr.deps, "runfiles_olean_dirs").to_list() +
        [result.runfiles_olean_dir, _stdlib_dir(tc, "short_path")],
    )

    script = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.write(
        output = script,
        is_executable = True,
        content = """#!/usr/bin/env bash
# Run the entry module with the Lean interpreter.
set -euo pipefail

RUNFILES="${{RUNFILES_DIR:-$0.runfiles}}"
cd "$RUNFILES/{workspace}"

# Nothing imports the entry, so only its own diagnostics use the module name.
LEAN_SRC="{entry}"
LEAN_MODREL="{module_rel}"

""".format(
            entry = entry.short_path,
            module_rel = _module_rel(ctx, entry),
            workspace = ctx.workspace_name,
        ) + _ROOT_SNIPPET + """
export LEAN_PATH="{lean_path}"
exec "{lean}" -R "$root" --run "$LEAN_SRC"
""".format(
            lean = tc.lean.short_path,
            lean_path = lean_path,
        ),
    )

    runfiles = ctx.runfiles(
        files = ctx.files.data + ctx.files.srcs + [tc.lean, entry] +
                tc.stdlib.to_list() +
                [file for info in dep_infos for file in info.oleans.to_list()],
    )

    return [DefaultInfo(executable = script, runfiles = runfiles)]

lean_test = rule(
    implementation = _lean_test_impl,
    attrs = {
        "data": attr.label_list(
            allow_files = True,
            doc = "Files the test reads at run time.",
        ),
        "deps": attr.label_list(
            providers = [LeanLibraryInfo],
            doc = "Lean libraries that the sources import.",
        ),
        "entry": attr.label(
            allow_single_file = [".lean"],
            mandatory = True,
            doc = "The `.lean` file to run. It must be one of `srcs`.",
        ),
        "extra_flags": attr.string_list(
            doc = "Extra flags for `lean`.",
        ),
        "srcs": attr.label_list(
            allow_files = [".lean"],
            mandatory = True,
            doc = "Lean sources of the test.",
        ),
    },
    test = True,
    toolchains = [TOOLCHAIN_TYPE],
    doc = "Compiles Lean sources and runs one of them with the interpreter.",
)

def _lean_binary_impl(ctx):
    tc = ctx.toolchains[TOOLCHAIN_TYPE].lean_toolchain

    # Every module of the dependency closure gets its own code-generation
    # action. The closure is the dep set, not the import graph, because the
    # rules do not read import lines yet (see M0b in the README).
    modules = {}
    for src in ctx.files.srcs:
        rel = _module_rel(ctx, src)
        modules[rel] = (rel, src)
    for info in [dep[LeanLibraryInfo] for dep in ctx.attr.deps]:
        for rel, name, file in info.module_sources.to_list():
            modules[name] = (rel, file)

    entry = modules.get(ctx.attr.main)
    if entry == None:
        fail("%s: no module named '%s'. Known modules: %s" % (
            ctx.label,
            ctx.attr.main,
            ", ".join(sorted(modules.keys())),
        ))

    # Lean searches LEAN_PATH in order and replaces its built-in path, so the
    # standard library must be an explicit entry.
    lean_path = ":".join(
        _transitive(ctx.attr.deps, "olean_dirs").to_list() + [_stdlib_dir(tc, "path")],
    )

    sources = []
    for rel, src in modules.values():
        olean = ctx.actions.declare_file("%s.oleans/%s.olean" % (ctx.label.name, rel))
        cfile = ctx.actions.declare_file("%s.c/%s.c" % (ctx.label.name, rel))

        # A native program needs the C code of every module it imports: the
        # generated C calls the initializer of each import.
        ctx.actions.run_shell(
            command = "set -euo pipefail\n\n" + _ROOT_SNIPPET + """
exec "{lean}" -o "$LEAN_OUT" -c "$LEAN_C" -R "$root" "$LEAN_SRC" "$@"
""".format(lean = tc.lean.path),
            arguments = ctx.attr.extra_flags,
            inputs = depset(
                direct = [src],
                transitive = [tc.stdlib, _transitive(ctx.attr.deps, "oleans")],
            ),
            outputs = [olean, cfile],
            tools = [tc.lean],
            env = {
                "LEAN_C": cfile.path,
                "LEAN_MODREL": rel,
                "LEAN_OUT": olean.path,
                "LEAN_PATH": lean_path,
                "LEAN_SRC": src.path,
            },
            mnemonic = "LeanCCode",
            progress_message = "Lean code %s" % rel,
        )
        sources.append(cfile)

    executable = ctx.actions.declare_file(ctx.label.name)
    args = ctx.actions.args()
    args.add("-o", executable.path)
    args.add_all(sources)
    args.add_all(ctx.attr.extra_link_flags)

    ctx.actions.run(
        executable = tc.leanc,
        arguments = [args],
        inputs = depset(sources, transitive = [tc.link_inputs]),
        outputs = [executable],
        tools = [tc.leanc],
        mnemonic = "LeanLink",
        progress_message = "Lean link %{label}",
    )

    # The link is static against the Lean runtime, so the runfiles hold the
    # data files only.
    runfiles = ctx.runfiles(files = ctx.files.data)

    return [DefaultInfo(executable = executable, runfiles = runfiles)]

lean_binary = rule(
    implementation = _lean_binary_impl,
    attrs = {
        "data": attr.label_list(
            allow_files = True,
            doc = "Files the program reads at run time.",
        ),
        "deps": attr.label_list(
            providers = [LeanLibraryInfo],
            doc = "Lean libraries that the program imports.",
        ),
        "extra_flags": attr.string_list(
            doc = "Extra flags for `lean`, for example [\"-DwarningAsError=true\"].",
        ),
        "extra_link_flags": attr.string_list(
            doc = "Extra flags for `leanc`, for example a `-l` flag.",
        ),
        "main": attr.string(
            mandatory = True,
            doc = "The module that holds `main`, as Lake's `root :=` names it. " +
                  "It must be one of `srcs` or of the modules of `deps`.",
        ),
        "srcs": attr.label_list(
            allow_files = [".lean"],
            doc = "Extra modules of the program. Keep them entry points: a " +
                  "module that others of `srcs` import belongs in a lean_library.",
        ),
    },
    executable = True,
    toolchains = [TOOLCHAIN_TYPE],
    doc = "Links a native executable from Lean sources.",
)
