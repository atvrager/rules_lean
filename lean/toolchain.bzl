"""The Lean toolchain type and the `lean_toolchain` rule."""

LeanToolchainInfo = provider(
    doc = "A Lean compiler installation.",
    fields = {
        "leanc": "File: the native linker driver.",
        "link_inputs": "depset[File]: files the linker reads, for `lean_binary`.",
        "lean": "File: the Lean binary.",
        "stdlib": "depset[File]: prebuilt oleans of the standard library.",
        "version": "str: the Lean version, for example \"4.34.1\".",
    },
)

TOOLCHAIN_TYPE = str(Label("//lean:toolchain_type"))


def _lean_toolchain_impl(ctx):
    info = LeanToolchainInfo(
        version = ctx.attr.version,
        lean = ctx.file.lean,
        leanc = ctx.file.leanc,
        link_inputs = ctx.attr.link[DefaultInfo].files,
        stdlib = ctx.attr.stdlib[DefaultInfo].files,
    )

    # A `toolchain()` target wraps this target and reads its ToolchainInfo.
    return [
        info,
        platform_common.ToolchainInfo(lean_toolchain = info),
    ]

lean_toolchain = rule(
    implementation = _lean_toolchain_impl,
    attrs = {
        "lean": attr.label(
            allow_single_file = True,
            mandatory = True,
            doc = "The `lean` binary.",
        ),
        "leanc": attr.label(
            allow_single_file = True,
            mandatory = True,
            doc = "The `leanc` binary, which links native executables.",
        ),
        "link": attr.label(
            mandatory = True,
            doc = "Target that provides the files the linker reads.",
        ),
        "stdlib": attr.label(
            mandatory = True,
            doc = "Target that provides the prebuilt standard library oleans.",
        ),
        "version": attr.string(
            mandatory = True,
            doc = "The Lean version. It must match the downloaded tarball.",
        ),
    },
    doc = "A Lean toolchain. Write one in a BUILD file to use a compiler that " +
          "the ruleset cannot download, for example a local build.",
)
