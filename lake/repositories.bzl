"""Repository rule for Lake packages from lake-manifest.json."""

def _parse_imports(text):
    """The module names the `import` lines of a file mention."""
    modules = []
    for line in text.split("\n"):
        line = line.strip()
        if "--" in line:
            line = line.split("--")[0].strip()
        words = [w for w in line.replace("\t", " ").split(" ") if w]
        if "import" in words:
            idx = words.index("import")
            if all([w in ["public", "meta", "scoped", "open", "all"] for w in words[:idx]]):
                modules += words[idx + 1:]
    return modules

def _find_src_dir(rctx):
    if rctx.attr.sub_dir:
        return rctx.attr.sub_dir
    config_file = rctx.attr.config_file or "lakefile.toml"
    p = rctx.path(config_file)
    if not p.exists:
        return ""
    content = rctx.read(p)
    for line in content.split("\n"):
        line = line.strip()
        if line.startswith("srcDir"):
            parts = line.split("=")
            if len(parts) == 2:
                return parts[1].strip().strip('"').strip("'")
    return ""

def _find_test_driver(rctx):
    config_file = rctx.attr.config_file or "lakefile.toml"
    p = rctx.path(config_file)
    if not p.exists:
        return ""
    content = rctx.read(p)
    for line in content.split("\n"):
        line = line.strip()
        if line.startswith("testDriver"):
            parts = line.split("=")
            if len(parts) == 2:
                return parts[1].strip().strip('"').strip("'")
    return ""

def _scan_lean_files(rctx, src_dir_str, test_driver):
    root = rctx.path(src_dir_str) if src_dir_str else rctx.path("")
    root_str = str(root)
    queue = [root]
    files = []
    for _ in range(5000):
        if not queue:
            break
        curr = queue.pop()
        for entry in curr.readdir():
            base = entry.basename
            if base.startswith(".") or base in ["test", "tests", "scripts", ".lake", test_driver]:
                continue
            if base.endswith("Test") or base.endswith("test"):
                continue
            if entry.is_dir:
                queue.append(entry)
            elif base.endswith(".lean"):
                entry_str = str(entry)
                rel = entry_str[len(root_str) + 1:] if root_str else entry_str
                files.append(rel)
    return sorted(files)

def _download_package(rctx):
    url = rctx.attr.url
    commit = rctx.attr.commit

    if url.startswith("https://github.com/"):
        clean_url = url
        if clean_url.endswith(".git"):
            clean_url = clean_url[:-4]
        clean_url = clean_url.rstrip("/")
        parts = clean_url.split("/")
        if len(parts) >= 5:
            owner = parts[3]
            repo = parts[4]
            archive_url = "https://github.com/%s/%s/archive/%s.tar.gz" % (owner, repo, commit)
            strip_prefix = "%s-%s" % (repo, commit)
            res = rctx.download_and_extract(
                url = archive_url,
                strip_prefix = strip_prefix,
                allow_fail = True,
            )
            if res.success:
                return

    # Fallback to git
    git = rctx.which("git")
    if not git:
        fail("git is required to fetch %s from %s" % (rctx.attr.pkg_name, url))

    res = rctx.execute([str(git), "init", "."])
    if res.return_code != 0:
        fail("git init failed for %s: %s" % (rctx.attr.pkg_name, res.stderr))
    res = rctx.execute([str(git), "remote", "add", "origin", url])
    if res.return_code != 0:
        fail("git remote add failed for %s: %s" % (rctx.attr.pkg_name, res.stderr))
    res = rctx.execute([str(git), "fetch", "--depth", "1", "origin", commit])
    if res.return_code != 0:
        res = rctx.execute([str(git), "fetch", "origin"])
        if res.return_code != 0:
            fail("git fetch failed for %s: %s" % (rctx.attr.pkg_name, res.stderr))
    res = rctx.execute([str(git), "checkout", commit])
    if res.return_code != 0:
        fail("git checkout failed for %s: %s" % (rctx.attr.pkg_name, res.stderr))

def _lake_package_repo_impl(rctx):
    _download_package(rctx)
    src_dir_str = _find_src_dir(rctx)
    test_driver = _find_test_driver(rctx)
    files = _scan_lean_files(rctx, src_dir_str, test_driver)

    modules = {}
    for f in files:
        if f.endswith(".lean"):
            mod = f[:-5].replace("/", ".")
            modules[mod] = f

    internal_imports = {}
    external_deps = []

    for mod, f in modules.items():
        file_path = rctx.path(src_dir_str).get_child(f) if src_dir_str else rctx.path(f)
        content = rctx.read(file_path)
        imps = _parse_imports(content)
        int_imps = []
        for imp in imps:
            if imp in modules:
                int_imps.append(imp)
            else:
                top = imp.split(".")[0]
                for p in rctx.attr.manifest_packages:
                    if p != rctx.attr.pkg_name and top.lower() == p.lower():
                        dep_label = "@%s//:%s" % (p, p)
                        if dep_label not in external_deps:
                            external_deps.append(dep_label)
        if int_imps:
            internal_imports[mod] = int_imps

    lines = [
        'load("@rules_lean//lean:defs.bzl", "lean_library")',
        "",
        'package(default_visibility = ["//visibility:public"])',
        "",
        "lean_library(",
        '    name = "%s",' % rctx.attr.pkg_name,
        "    srcs = [",
    ]
    for f in files:
        lines.append('        "%s",' % f)
    lines.append("    ],")

    if internal_imports:
        lines.append("    internal_imports = {")
        for m, imps in sorted(internal_imports.items()):
            lines.append('        "%s": %s,' % (m, repr(imps)))
        lines.append("    },")

    if external_deps:
        lines.append("    deps = [")
        for d in sorted(external_deps):
            lines.append('        "%s",' % d)
        lines.append("    ],")

    lines.append(")")
    lines.append("")

    build_content = "\n".join(lines)
    if src_dir_str:
        rctx.file(src_dir_str + "/BUILD.bazel", build_content)
        root_build = """package(default_visibility = ["//visibility:public"])

alias(
    name = "{name}",
    actual = "//{src_dir}:{name}",
)
""".format(name = rctx.attr.pkg_name, src_dir = src_dir_str)
        rctx.file("BUILD.bazel", root_build)
    else:
        rctx.file("BUILD.bazel", build_content)

_lake_package_repo = repository_rule(
    implementation = _lake_package_repo_impl,
    attrs = {
        "commit": attr.string(mandatory = True),
        "config_file": attr.string(default = ""),
        "manifest_packages": attr.string_list(),
        "pkg_name": attr.string(mandatory = True),
        "sub_dir": attr.string(default = ""),
        "url": attr.string(mandatory = True),
    },
    doc = "Fetches a git dependency defined in lake-manifest.json and builds it with lean_library.",
)

def lake_package_repo(name, pkg_name, url, commit, sub_dir = "", config_file = "", manifest_packages = []):
    _lake_package_repo(
        name = name,
        commit = commit,
        config_file = config_file,
        manifest_packages = manifest_packages,
        pkg_name = pkg_name,
        sub_dir = sub_dir,
        url = url,
    )
