"""The `lean` module extension: Lean toolchains.

    lean = use_extension("@rules_lean//lean:extensions.bzl", "lean")
    lean.toolchain(toolchain_file = "//:lean-toolchain")

    use_repo(lean, "lean_toolchains")
    register_toolchains("@lean_toolchains//:all")
"""

load("//lean/private:repositories.bzl", "lean_imports_repo", "lean_toolchain_repo", "lean_toolchains_repo")
load(
    "//lean/private:versions.bzl",
    "KNOWN_VERSIONS",
    "PLATFORM_ASSETS",
    "parse_toolchain_file",
    "repo_suffix",
)

_HUB = "lean_toolchains"

_TOOLCHAIN_TAG = tag_class(
    attrs = {
        "platforms": attr.string_list(
            default = sorted(PLATFORM_ASSETS.keys()),
            doc = "Platforms to declare. Defaults to all known platforms.",
        ),
        "sha256": attr.string_dict(
            doc = "Platform key -> sha256 of the release tarball. Required for a " +
                  "version outside the built-in table.",
        ),
        "toolchain_file": attr.label(
            allow_single_file = True,
            doc = "The `lean-toolchain` file of this module. The version in that " +
                  "file is the version of the toolchain.",
        ),
        "version": attr.string(
            doc = "A Lean version, for example \"4.34.1\". Use this only when the " +
                  "module has no `lean-toolchain` file.",
        ),
    },
    doc = "Declares a Lean toolchain.",
)

def _resolve_version(mctx, mod, tag):
    """Return the version for one tag, and check the two attributes agree."""

    file_version = None
    if tag.toolchain_file:
        content = mctx.read(tag.toolchain_file)
        file_version = parse_toolchain_file(content)

    if tag.version and file_version and tag.version != file_version:
        fail(("module %s: lean.toolchain(version = \"%s\") disagrees with %s, " +
              "which holds \"%s\". Keep one of the two, or make them equal.") % (
            mod.name,
            tag.version,
            tag.toolchain_file,
            file_version,
        ))

    version = tag.version or file_version
    if not version:
        fail("module %s: lean.toolchain needs toolchain_file or version" % mod.name)
    return version

def _shas_for(tag, version):
    """Return the platform -> sha256 map for one tag."""
    shas = dict(KNOWN_VERSIONS.get(version, {}))
    shas.update(tag.sha256)

    missing = [p for p in tag.platforms if p not in shas]
    if missing:
        fail(("no sha256 for Lean %s on %s. Add the version to " +
              "lean/private/versions.bzl, or pass sha256 = {\"%s\": \"...\"}.") % (
            version,
            ", ".join(missing),
            missing[0],
        ))
    return shas

def _lean_impl(mctx):
    # Deduplicate: two modules may request the same version.
    requested = {}

    for mod in mctx.modules:
        for tag in mod.tags.toolchain:
            version = _resolve_version(mctx, mod, tag)
            for platform, sha256 in _shas_for(tag, version).items():
                if platform not in tag.platforms:
                    continue
                key = (version, platform)
                if key in requested and requested[key] != sha256:
                    fail("two sha256 values for Lean %s on %s" % (version, platform))
                requested[key] = sha256

    entries = []
    for (version, platform) in sorted(requested.keys()):
        repo = "lean_toolchain_" + repo_suffix(version, platform)
        lean_toolchain_repo(
            name = repo,
            platform = platform,
            sha256 = requested[(version, platform)],
            version = version,
        )
        entries.append("%s %s %s" % (version, platform, repo))

    lean_toolchains_repo(name = _HUB, entries = entries)

    root_labels = [Label("@@//:MODULE.bazel")]
    if Label("@@//:MODULE.bazel") != Label("//:MODULE.bazel"):
        root_labels.append(Label("//:MODULE.bazel"))
    lean_imports_repo(name = "lean_imports", roots = root_labels)

    is_rules_lean_root = any([mod.is_root and mod.name == "rules_lean" for mod in mctx.modules])
    root_deps = [_HUB, "lean_imports"] if is_rules_lean_root else [_HUB]

    return mctx.extension_metadata(
        root_module_direct_deps = root_deps,
        root_module_direct_dev_deps = [],
        reproducible = True,
    )

lean = module_extension(
    implementation = _lean_impl,
    tag_classes = {"toolchain": _TOOLCHAIN_TAG},
)
