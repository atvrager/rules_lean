"""The `upstream` extension: the Lean compiler test suite, as Bazel targets.

    upstream = use_extension("//upstream:extensions.bzl", "upstream")
    upstream.samples(tag = "v4.34.1", sha256 = "...", piles = {...})
    use_repo(upstream, "lean_samples")

The generated repository unpacks the upstream archive and writes one
`BUILD.bazel` per pile, with one target per test file and dep edges taken from
the `import` lines of each file.
"""

load("//upstream:repo.bzl", "lean_samples_repo")

# The generated repository cannot see @rules_lean by its apparent name, so the
# load label is made canonical here. The apparent name resolves because the
# module that uses this extension depends on rules_lean.
_DEFS_BZL = str(Label("@rules_lean//lean:defs.bzl"))

_SAMPLES_TAG = tag_class(
    attrs = {
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
        "native_piles": attr.string_list(
            doc = "Pile names that also get a native executable, for example " +
                  "`compile`.",
        ),
        "piles": attr.string_dict(
            doc = "Pile name to directory inside the upstream archive.",
        ),
        "sha256": attr.string(
            mandatory = True,
            doc = "sha256 of the archive of the tag.",
        ),
        "tag": attr.string(
            mandatory = True,
            doc = "The upstream tag, which must match the Lean toolchain version.",
        ),
    },
    doc = "Declare the upstream test piles to fetch and generate.",
)

def _upstream_impl(mctx):
    for mod in mctx.modules:
        for tag in mod.tags.samples:
            lean_samples_repo(
                name = "lean_samples",
                defs_bzl = _DEFS_BZL,
                excluded_piles = tag.excluded_piles,
                excludes = tag.excludes,
                flags = tag.flags,
                link_flags = tag.link_flags,
                native_piles = tag.native_piles,
                piles = tag.piles,
                sha256 = tag.sha256,
                tag = tag.tag,
            )

    return mctx.extension_metadata(
        root_module_direct_deps = ["lean_samples"],
        root_module_direct_dev_deps = [],
        reproducible = True,
    )

upstream = module_extension(
    implementation = _upstream_impl,
    tag_classes = {"samples": _SAMPLES_TAG},
)
