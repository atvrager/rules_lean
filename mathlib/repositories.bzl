"""Repository rule for prebuilt Mathlib oleans."""

_BUILD_TEMPLATE = """load("@rules_lean//lean:defs.bzl", "lean_prebuilt_library")

package(default_visibility = ["//visibility:public"])

lean_prebuilt_library(
    name = "mathlib",
    srcs = glob([
        "lib/lean/**/*.olean*",
        "lib/lean/**/*.ir*",
        "lib/lean/**/*.ilean*",
    ]),
    root = "lib/lean",
)
"""

_LINK_SCRIPT = """
import os, sys

target = sys.argv[1]
lib = os.path.join(target, "lib", "lean")
os.makedirs(lib, exist_ok=True)

src_dir = os.path.join(target, ".lake", "build", "lib", "lean")
if os.path.isdir(src_dir):
    for item in os.listdir(src_dir):
        src = os.path.join(src_dir, item)
        dst = os.path.join(lib, item)
        if not os.path.exists(dst):
            os.symlink(os.path.relpath(src, lib), dst)

pkgs_dir = os.path.join(target, ".lake", "packages")
if os.path.isdir(pkgs_dir):
    for pkg in os.listdir(pkgs_dir):
        pkg_build = os.path.join(pkgs_dir, pkg, ".lake", "build", "lib", "lean")
        if os.path.isdir(pkg_build):
            for item in os.listdir(pkg_build):
                src = os.path.join(pkg_build, item)
                dst = os.path.join(lib, item)
                if not os.path.exists(dst):
                    os.symlink(os.path.relpath(src, lib), dst)
"""

# Known Mathlib release tarball SHA256 hashes
MATHLIB_SHAS = {
    "4.34.1": "c586ce5d3f83f85903826b613347b81e9eb6da885ecbbf22f72b2a3197a2904e",
}

def _mathlib_repo_impl(rctx):
    os_name = rctx.os.name.lower()
    os_arch = rctx.os.arch.lower()
    if "linux" in os_name:
        platform = "linux_x86_64" if os_arch in ["x86_64", "amd64"] else "linux_aarch64"
    elif "mac" in os_name or "darwin" in os_name:
        platform = "darwin_aarch64" if os_arch in ["aarch64", "arm64"] else "darwin_x86_64"
    else:
        fail("Unsupported host platform for Mathlib: %s %s" % (os_name, os_arch))

    lake_label = rctx.attr.toolchain_lakes.get(platform)
    if not lake_label:
        fail("No lake toolchain for platform %s" % platform)

    lake_path = rctx.path(lake_label)
    bin_dir = lake_path.dirname

    version = rctx.attr.version
    tag = "v" + version if not version.startswith("v") else version
    raw_version = version[1:] if version.startswith("v") else version

    sha256 = rctx.attr.sha256 or MATHLIB_SHAS.get(raw_version, "")
    if not sha256:
        fail("No sha256 known for Mathlib version %s. Specify sha256 attribute." % version)

    rctx.report_progress("Downloading Mathlib %s source" % tag)
    result = rctx.download_and_extract(
        url = "https://github.com/leanprover-community/mathlib4/archive/refs/tags/%s.tar.gz" % tag,
        sha256 = sha256,
        strip_prefix = "mathlib4-%s" % raw_version,
    )

    python = rctx.which("python3") or rctx.which("python")
    if not python:
        fail("python3 or python required in PATH to link Mathlib oleans")

    if rctx.attr.fetcher == "direct":
        cache_dir = rctx.path(".cache")
        cache_cmd = [str(lake_path), "exe", "cache", "get-"]
        if rctx.attr.modules:
            cache_cmd.extend(rctx.attr.modules)
        rctx.report_progress("Downloading Mathlib .ltar archives")
        res = rctx.execute(
            cache_cmd,
            environment = {
                "HOME": str(rctx.os.environ.get("HOME", "/tmp")),
                "MATHLIB_CACHE_DIR": str(cache_dir),
                "PATH": str(bin_dir) + ":/bin:/usr/bin:/usr/local/bin",
            },
            timeout = 900,
        )
        if res.return_code != 0:
            fail("Direct cache download failed (exit code %d):\n%s\n%s" % (res.return_code, res.stdout, res.stderr))

        rctx.report_progress("Extracting Mathlib archives with leantar")
        leantar_path = str(bin_dir) + "/leantar"
        res = rctx.execute([
            str(python),
            "-c",
            """
import os, subprocess, sys
td = sys.argv[1]
leantar = sys.argv[2]
ltars = [os.path.join(td, f) for f in os.listdir(td) if f.endswith('.ltar')]
for ltar in ltars:
    subprocess.check_call([leantar, '-x', '-f', ltar])
""",
            str(cache_dir),
            leantar_path,
        ])
        if res.return_code != 0:
            fail("leantar extraction failed:\n%s\n%s" % (res.stdout, res.stderr))
    else:
        cache_cmd = [str(lake_path), "exe", "cache", "get"]
        if rctx.attr.modules:
            cache_cmd.extend(rctx.attr.modules)

        rctx.report_progress("Fetching Mathlib oleans with lake cache get")
        res = rctx.execute(
            cache_cmd,
            environment = {
                "HOME": str(rctx.os.environ.get("HOME", "/tmp")),
                "PATH": str(bin_dir) + ":/bin:/usr/bin:/usr/local/bin",
            },
            timeout = 900,
        )
        if res.return_code != 0:
            fail("lake exe cache get failed (exit code %d):\n%s\n%s" % (res.return_code, res.stdout, res.stderr))

    res = rctx.execute([str(python), "-c", _LINK_SCRIPT, str(rctx.path(""))])
    if res.return_code != 0:
        fail("Failed to link Mathlib oleans:\n%s\n%s" % (res.stdout, res.stderr))

    rctx.file("BUILD.bazel", _BUILD_TEMPLATE)

_mathlib_repo = repository_rule(
    implementation = _mathlib_repo_impl,
    attrs = {
        "fetcher": attr.string(
            default = "lake",
            doc = "Backend to fetch Mathlib oleans: 'lake' or 'direct'.",
            values = ["lake", "direct"],
        ),
        "modules": attr.string_list(
            doc = "Optional subset of modules to fetch. If empty, fetches all cache files.",
        ),
        "sha256": attr.string(
            doc = "SHA256 of Mathlib release tarball.",
        ),
        "toolchain_lakes": attr.string_keyed_label_dict(
            mandatory = True,
            doc = "Mapping from platform to lake binary label.",
        ),
        "version": attr.string(
            default = "4.34.1",
            doc = "Mathlib version tag.",
        ),
    },
    doc = "Downloads Mathlib source, runs lake cache get, and provides prebuilt oleans.",
)

def mathlib_repo(name, toolchain_lakes, version = "4.34.1", sha256 = "", modules = [], fetcher = "lake"):
    _mathlib_repo(
        name = name,
        fetcher = fetcher,
        modules = modules,
        sha256 = sha256,
        toolchain_lakes = toolchain_lakes,
        version = version,
    )
