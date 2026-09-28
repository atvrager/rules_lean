"""Repository rules for Lean toolchains.

Two levels, as in other toolchain rulesets:

1. One repository per (version, platform) holds the unpacked release tarball
   and one `lean_toolchain` target.
2. One hub repository holds one `toolchain` target per (version, platform).
   `register_toolchains("@lean_toolchains//:all")` points at it.
"""

load("//lean/private:versions.bzl", "PLATFORM_CONSTRAINTS", "asset_prefix", "release_url")

_TOOLCHAIN_BZL = str(Label("//lean:toolchain.bzl"))
_TOOLCHAIN_TYPE = str(Label("//lean:toolchain_type"))

# The loader opens five files per imported module: `.olean`, `.olean.private`,
# `.olean.server`, `.ir`, and `.ir.sig` (measured with strace on 4.34.1). The
# `.so` files are the shared library of the compiler itself.
_STDLIB_GLOBS = [
    "lib/lean/**/*.ir",
    "lib/lean/**/*.ir.sig",
    "lib/lean/**/*.olean*",
    "lib/lean/*.so*",
]

_PLATFORM_REPO_TEMPLATE = """load("{toolchain_bzl}", "lean_toolchain")

# The standard library oleans that ship with the release tarball. The build never
# compiles them.
filegroup(
    name = "stdlib",
    srcs = glob(
        [
{stdlib_globs}
        ],
        allow_empty = False,
    ),
    visibility = ["//visibility:public"],
)

# Everything the native link needs: the driver, the bundled clang with its
# resource directory, the bundled libc, and the static libraries of the
# compiler and its runtime.
filegroup(
    name = "link",
    srcs = glob(
        [
            "bin/clang",
            "bin/ld.lld",
            "bin/leanc",
            "include/**",
            "lib/*.a",
            "lib/*.so*",
            "lib/clang/**",
            "lib/glibc/**",
            "lib/lean/*.a",
            "lib/lean/*.so*",
        ],
        allow_empty = False,
    ),
    visibility = ["//visibility:public"],
)

lean_toolchain(
    name = "lean_toolchain",
    version = "{version}",
    lean = "bin/lean",
    leanc = "bin/leanc",
    link = ":link",
    stdlib = ":stdlib",
    visibility = ["//visibility:public"],
)
"""

def _lean_toolchain_repo_impl(rctx):
    version = rctx.attr.version
    platform = rctx.attr.platform

    rctx.report_progress("Downloading Lean %s for %s" % (version, platform))

    result = rctx.download_and_extract(
        url = rctx.attr.urls,
        sha256 = rctx.attr.sha256,
        strip_prefix = asset_prefix(version, platform),
        allow_fail = True,
    )
    if not result.success:
        fail("could not unpack Lean %s for %s: %s" % (version, platform, result.error))

    rctx.file("BUILD.bazel", _PLATFORM_REPO_TEMPLATE.format(
        stdlib_globs = "\n".join(['            "%s",' % g for g in _STDLIB_GLOBS]),
        toolchain_bzl = _TOOLCHAIN_BZL,
        version = version,
    ))

_lean_toolchain_repo = repository_rule(
    implementation = _lean_toolchain_repo_impl,
    attrs = {
        "platform": attr.string(mandatory = True),
        "sha256": attr.string(mandatory = True),
        "urls": attr.string_list(mandatory = True),
        "version": attr.string(mandatory = True),
    },
    doc = "Downloads one Lean release tarball and declares a `lean_toolchain`.",
)

def lean_toolchain_repo(name, version, platform, sha256):
    """Declare the repository that holds one unpacked Lean toolchain."""
    _lean_toolchain_repo(
        name = name,
        platform = platform,
        sha256 = sha256,
        urls = [release_url(version, platform)],
        version = version,
    )

def _lean_toolchains_repo_impl(rctx):
    lines = []

    # One `toolchain` target per (version, platform). A `toolchain` target holds
    # the constraints that select it: Bazel picks the entry whose execution
    # platform matches the host.
    for entry in rctx.attr.entries:
        version, platform, repo = entry.split(" ")
        constraints = ", ".join(['"%s"' % c for c in PLATFORM_CONSTRAINTS[platform]])
        lines.append("""
toolchain(
    name = "{name}",
    toolchain = "@{repo}//:lean_toolchain",
    toolchain_type = "{toolchain_type}",
    exec_compatible_with = [{constraints}],
)
""".format(
            name = "lean_%s_%s" % (version.replace(".", "_").replace("-", "_"), platform),
            repo = repo,
            toolchain_type = _TOOLCHAIN_TYPE,
            constraints = constraints,
        ))

    rctx.file("BUILD.bazel", "".join(lines))

_lean_toolchains_repo = repository_rule(
    implementation = _lean_toolchains_repo_impl,
    attrs = {
        "entries": attr.string_list(),
    },
    doc = "Declares one `toolchain` target per (version, platform) entry.",
)

def lean_toolchains_repo(name, entries):
    """Declare the hub repository.

    Args:
      name: repository name.
      entries: strings of the form "<version> <platform> <repo>".
    """
    _lean_toolchains_repo(name = name, entries = entries)

def _parse_imports(text):
    """The module names the `import` lines of a file mention."""
    modules = []
    for line in text.split("\n"):
        line = line.strip()
        if "--" in line:
            line = line.split("--")[0].strip()
        if not line.startswith("import"):
            continue
        words = [w for w in line.replace("\t", " ").split(" ") if w]
        if words and words[0] == "import":
            modules += words[1:]
    return modules

def _lean_imports_repo_impl(rctx):
    imports_by_pkg = {}

    for root_lbl in rctx.attr.roots:
        root_dir = rctx.path(root_lbl).dirname
        root_dir_str = str(root_dir)

        root_has_build = (root_dir.get_child("BUILD.bazel").exists or
                          root_dir.get_child("BUILD").exists)
        queue = [(root_dir, "" if root_has_build else None)]

        for _ in range(5000):
            if not queue:
                break
            curr_dir, curr_pkg = queue.pop()

            is_pkg = (curr_dir.get_child("BUILD.bazel").exists or
                      curr_dir.get_child("BUILD").exists)
            if is_pkg:
                curr_str = str(curr_dir)
                if curr_str == root_dir_str:
                    curr_pkg = ""
                else:
                    curr_pkg = curr_str[len(root_dir_str) + 1:]
                if curr_pkg not in imports_by_pkg:
                    imports_by_pkg[curr_pkg] = {}

            for entry in curr_dir.readdir():
                base = entry.basename
                if base.startswith(".") or base.startswith("bazel-") or base in ["build", "out", "external"]:
                    continue
                if entry.is_dir:
                    if entry != root_dir and entry.get_child("MODULE.bazel").exists:
                        continue
                    queue.append((entry, curr_pkg))
                elif base.endswith(".lean") and curr_pkg != None:
                    entry_str = str(entry)
                    if curr_pkg == "":
                        rel_in_pkg = entry_str[len(root_dir_str) + 1:]
                    else:
                        pkg_dir_str = root_dir_str + "/" + curr_pkg
                        rel_in_pkg = entry_str[len(pkg_dir_str) + 1:]

                    if rel_in_pkg.endswith(".lean"):
                        module_rel = rel_in_pkg[:-len(".lean")]
                        module_name = module_rel.replace("/", ".")
                        content = rctx.read(entry)
                        imports_by_pkg[curr_pkg][module_name] = _parse_imports(content)

    rctx.file("BUILD.bazel", "exports_files(['imports.bzl'])\n")
    rctx.file("imports.bzl", "IMPORTS = " + repr(imports_by_pkg) + "\n")

_lean_imports_repo = repository_rule(
    implementation = _lean_imports_repo_impl,
    attrs = {
        "roots": attr.label_list(
            mandatory = True,
            doc = "Labels to MODULE.bazel files of modules to scan for Lean sources.",
        ),
    },
    doc = "Scans Lean source files for import lines and writes imports.bzl.",
)

def lean_imports_repo(name, roots):
    _lean_imports_repo(name = name, roots = roots)
