"""Lean 4 release tarballs: platform assets and sha256 sums.

A version key is the release tag without the leading `v`: "4.34.1" is the tag
`v4.34.1`. The asset name is `lean-<version>-<asset>.tar.zst`.

Values come from the GitHub release assets. Each asset publishes a sha256
digest:

    curl -sSL https://api.github.com/repos/leanprover/lean4/releases/tags/v4.34.1 \
      | grep -E '"(name|digest)"'

Add an entry for each version a project needs. A version outside this table
requires an explicit `sha256` from the user, because the ruleset never unpacks
an unverified tarball.
"""

# Platform key -> asset suffix in the release file name.
PLATFORM_ASSETS = {
    "linux_aarch64": "linux_aarch64",
    "linux_x86_64": "linux",
    "darwin_aarch64": "darwin_aarch64",
    "darwin_x86_64": "darwin",
}

# Platform key -> execution constraints. Canonical labels, so that a generated
# repository resolves them without a mapping entry.
_PLATFORM_OS = {
    "linux_aarch64": "linux",
    "linux_x86_64": "linux",
    "darwin_aarch64": "macos",
    "darwin_x86_64": "macos",
}

_PLATFORM_CPU = {
    "linux_aarch64": "aarch64",
    "linux_x86_64": "x86_64",
    "darwin_aarch64": "aarch64",
    "darwin_x86_64": "x86_64",
}

PLATFORM_CONSTRAINTS = {
    key: [
        str(Label("@platforms//os:" + _PLATFORM_OS[key])),
        str(Label("@platforms//cpu:" + _PLATFORM_CPU[key])),
    ]
    for key in PLATFORM_ASSETS
}

KNOWN_VERSIONS = {
    "4.29.1": {
        "darwin_aarch64": "73bccb392ca7d8ab3d62a1e328bb7d057815f088dbdbfb6574f194ae505797af",
        "darwin_x86_64": "3585ab34d20c53cf915169aa5c0d2efbd9993a78b9dc08516641510eef08fab0",
        "linux_aarch64": "1ccdfb7f924901f4b73a4b4eb169e5b3dc74f6836521b47e733ea25f2abfc0dc",
        "linux_x86_64": "bf062d29556d655685fb287563c249ad6a8fde34352c18b5e32568a595c1aec1",
    },
    "4.32.2": {
        "darwin_aarch64": "ea99ead969901b9fe4c7e7bf350b812a0249e9a5cea20474a737c0cc64746bc0",
        "darwin_x86_64": "2ce646cca9cab59886303a74a12e3a53065f851baac7dc8672782cc0c2d3b408",
        "linux_aarch64": "79aee7ec90f721757d43f75d75fe2e659ded07f0b4e5f1569e92ac9a183e3f81",
        "linux_x86_64": "5f2069e6f5db73780f374ccb49ce8ea649aa20a0cebf0116816744c999ce72aa",
    },
    "4.34.0-rc1": {
        "darwin_aarch64": "ae1f70cd5a72eeb93f8600edfeaed8550b9c9b073f04162ab6d721ab801ed709",
        "darwin_x86_64": "c011bf88cd984cab01d2be5b0ed98e1a23aa744ad5f8cf77e6f5c8cec82e63f9",
        "linux_aarch64": "e5b8ca631c1a5dce9e8477664f01543cf192737d63b3fbef43f3fae176efdabe",
        "linux_x86_64": "41dc6a6ec143ece8ed4ba4c4c6978c91f21ad5cbe3c4e7728ad31b869961dc17",
    },
    "4.34.1": {
        "darwin_aarch64": "65f22a4f047738ec742667b3247e836a86ebf06eabc12655c3dee00637e37866",
        "darwin_x86_64": "c2fee70250444e46c1106a27bddfef948d1e563eef431eaac05bb946b2f73d3a",
        "linux_aarch64": "fdb974c2cdb4627e090d5d4007b913e09d13c4868720fb5594e22808b3de9e37",
        "linux_x86_64": "47bf4bbd78f70c2e9670598ab7124d92b6efb7330ff33e5fbb4030f6fd72e4e4",
    },
}

def parse_toolchain_file(content):
    """Return the version in a `lean-toolchain` file.

    Example: "leanprover/lean4:v4.34.1\\n" -> "4.34.1".

    Args:
      content: String content of the lean-toolchain file.

    Returns:
      The parsed version string.
    """

    spec = content.strip()
    if not spec:
        fail("lean-toolchain file is empty")
    if ":" in spec:
        spec = spec.split(":")[-1].strip()
    elif "/" in spec:
        fail("lean-toolchain file has no version after ':': '%s'" % spec)
    if spec.startswith("v") and len(spec) > 1 and spec[1].isdigit():
        spec = spec[1:]
    if not spec:
        fail("lean-toolchain file has an empty version")
    return spec

def release_tag(version):
    """Return the GitHub release tag for a version: "4.34.1" -> "v4.34.1"."""
    if version and version[0].isdigit():
        return "v" + version
    return version

def asset_name(version, platform):
    return "lean-%s-%s.tar.zst" % (version, PLATFORM_ASSETS[platform])

def asset_prefix(version, platform):
    return "lean-%s-%s" % (version, PLATFORM_ASSETS[platform])

def release_url(version, platform):
    return "https://github.com/leanprover/lean4/releases/download/%s/%s" % (
        release_tag(version),
        asset_name(version, platform),
    )

def repo_suffix(version, platform):
    """Repository-name suffix for a (version, platform) pair."""
    return "%s_%s" % (version.replace(".", "_").replace("-", "_"), platform)
