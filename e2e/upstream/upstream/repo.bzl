"""Unpacks the Lean archive and writes one BUILD.bazel per pile parent.

A Bazel *rule* cannot read a source file during analysis (`ctx.read` does not
exist on Bazel 9.2.0), so the import scan happens here, in a repository rule,
which may read every file. The generated `deps` are therefore the exact import
edges, and each pile builds with one action per file.

Module names follow the upstream driver: it runs `lean --root=..` with the pile
directory as the working directory, so `tests/elab/10067.lean` is the module
`elab.10067`. The generated BUILD file therefore lives in the *parent* of the
pile, which makes Bazel's package directory the same root as upstream's.
"""

_BUILD_HEADER = """load("{defs_bzl}", "lean_binary", "lean_library")

# Generated from {tag}. Do not edit: the generator in e2e/upstream rewrites it.

package(default_visibility = ["//visibility:public"])

"""

_LIBRARY = """lean_library(
    name = "{name}",
    srcs = ["{src}"],{deps}{flags}{env}
)

"""

_BINARY = """lean_binary(
    name = "{name}_bin",
    main = "{module}",
    deps = [":{name}"],{link_flags}
)

"""

_SUITE = """filegroup(
    name = "pile_{pile}",
    srcs = [
{targets}    ],
)

"""

def _imports(text):
    """The module names the `import` lines of a file mention."""
    modules = []
    for line in text.split("\n"):
        line = line.strip()
        if not line.startswith("import"):
            continue
        words = [w for w in line.replace("\t", " ").split(" ") if w]
        if words and words[0] == "import":
            modules += words[1:]
    return modules

def _module_of(package, path):
    """The Lean module name of a file, with Bazel's package dir as the root."""
    rel = path
    if package:
        rel = path[len(package) + 1:] if path.startswith(package + "/") else path
    return rel[:-len(".lean")].replace("/", ".")

def _stem(module):
    return module.replace(".", "_")

def _parent(path):
    parts = path.split("/")
    return "/".join(parts[:-1])

def _init_env(rctx, path):
    """The `export` lines of a test's `.init.sh` file, as the driver reads them.

    Upstream runs each test with the environment of `<file>.init.sh`. One file
    changes Lean's own environment: `nat_size_limit.lean.init.sh` sets
    `LEAN_NAT_MAX_SIZE=16`.
    """
    if not rctx.path(path + ".init.sh").exists:
        return {}

    env = {}
    for line in rctx.read(path + ".init.sh").split("\n"):
        line = line.strip()
        if not line.startswith("export ") or "=" not in line:
            continue
        name, _, value = line[len("export "):].partition("=")
        env[name.strip()] = value.strip().strip('"')
    return env

def _lean_files(rctx, pile):
    """Every .lean file of a pile, relative to the repository root."""
    result = rctx.execute(["/usr/bin/env", "find", pile, "-name", "*.lean"])
    if result.return_code != 0:
        fail("find failed in %s: %s" % (pile, result.stderr))
    return [line for line in result.stdout.split("\n") if line]

def _samples_repo_impl(rctx):
    tag = rctx.attr.tag
    version = tag[1:] if tag.startswith("v") else tag

    rctx.report_progress("Downloading Lean %s" % tag)
    rctx.download_and_extract(
        url = "https://github.com/leanprover/lean4/archive/refs/tags/%s.tar.gz" % tag,
        sha256 = rctx.attr.sha256,
        strip_prefix = "lean4-%s" % version,
    )

    # Pass 1: list the files, and remember the package directory of each pile.
    files = {}
    packages = {}
    for pile, pile_dir in rctx.attr.piles.items():
        packages[pile] = _parent(pile_dir)
        files[pile] = [
            path
            for path in _lean_files(rctx, pile_dir)
            if path not in rctx.attr.excludes
        ]

    # Pass 2: module name -> label, so an import can be resolved to a target.
    labels = {}
    for pile, paths in files.items():
        for path in paths:
            module = _module_of(packages[pile], path)
            labels[module] = "//%s:%s" % (packages[pile], _stem(module))

    # Pass 3: one package per pile parent, one target per file.
    by_package = {}
    for pile, paths in files.items():
        by_package.setdefault(packages[pile], []).append((pile, paths))

    for package, piles in by_package.items():
        body = ""
        for pile, paths in piles:
            flags = rctx.attr.flags.get(pile, [])
            native = pile in rctx.attr.native_piles

            body += '# pile "%s": %s\n' % (pile, rctx.attr.piles[pile])
            targets = []
            for path in paths:
                module = _module_of(package, path)
                name = _stem(module)

                deps = [
                    labels[dep]
                    for dep in _imports(rctx.read(path))
                    if dep in labels and dep != module
                ]

                env = _init_env(rctx, path)
                body += _LIBRARY.format(
                    deps = "\n    deps = [\n" + "".join(
                        ['        "%s",\n' % dep for dep in deps]
                    ) + "    ]," if deps else "",
                    env = "\n    extra_env = {\n" + "".join(
                        ['        "%s": "%s",\n' % (name, value) for name, value in sorted(env.items())]
                    ) + "    }," if env else "",
                    flags = "\n    extra_flags = [\n" + "".join(
                        ['        "%s",\n' % flag for flag in flags]
                    ) + "    ]," if flags else "",
                    name = name,
                    # Paths in a BUILD file are relative to its package.
                    src = path[len(package) + 1:] if package else path,
                )
                targets.append(name)

                if native:
                    body += _BINARY.format(
                        link_flags = "\n    extra_link_flags = [\n" + "".join(
                            ['        "%s",\n' % flag for flag in rctx.attr.link_flags]
                        ) + "    ]," if rctx.attr.link_flags else "",
                        module = module,
                        name = name,
                    )
                    targets.append(name + "_bin")

            body += _SUITE.format(
                pile = pile,
                targets = "".join(['        ":%s",\n' % t for t in targets]),
            )

        body += _SUITE.format(
            pile = "all",
            targets = "".join([
                '        ":pile_%s",\n' % pile
                for pile, _ in piles
            ]),
        )
        rctx.file("%s/BUILD.bazel" % package, _BUILD_HEADER.format(
            defs_bzl = rctx.attr.defs_bzl,
            tag = tag,
        ) + body)

    # A placeholder for the piles that are known and not generated yet, so the
    # gap is visible in the repository instead of silently missing.
    if rctx.attr.excluded_piles:
        rctx.file("EXCLUDED.md", "\n".join([
            "# Piles that this repository does not generate",
            "",
            "| Pile | Reason |",
            "| --- | --- |",
        ] + [
            "| `%s` | %s |" % (pile, reason)
            for pile, reason in sorted(rctx.attr.excluded_piles.items())
        ]) + "\n")

lean_samples_repo = repository_rule(
    implementation = _samples_repo_impl,
    attrs = {
        "defs_bzl": attr.string(
            mandatory = True,
            doc = "Canonical label of the public defs.bzl, because the generated " +
                  "repository cannot see @rules_lean by its apparent name.",
        ),
        "excluded_piles": attr.string_dict(
            doc = "Pile name to the reason it is not generated.",
        ),
        "excludes": attr.string_list(
            doc = "File paths to skip, as the upstream driver skips them.",
        ),
        "flags": attr.string_list_dict(
            doc = "Pile name to the `-D` flags of the upstream driver.",
        ),
        "link_flags": attr.string_list(
            doc = "Link flags for the native piles.",
        ),
        "native_piles": attr.string_list(),
        "piles": attr.string_dict(mandatory = True),
        "sha256": attr.string(mandatory = True),
        "tag": attr.string(mandatory = True),
    },
    doc = "Fetches the upstream archive and generates one BUILD.bazel per pile.",
)
