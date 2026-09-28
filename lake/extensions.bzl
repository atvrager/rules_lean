"""Bzlmod extension for Lake packages defined in lake-manifest.json."""

load("//lake:repositories.bzl", "lake_package_repo")

_MANIFEST_TAG = tag_class(
    attrs = {
        "manifest": attr.label(
            doc = "Label to lake-manifest.json file.",
            mandatory = True,
        ),
        "packages": attr.string_list(
            doc = "Optional subset of packages to import. If empty, imports all packages.",
        ),
    },
)

def _lake_impl(mctx):
    repos = {}
    for mod in mctx.modules:
        for tag in mod.tags.manifest:
            manifest_content = mctx.read(tag.manifest)
            manifest_json = json.decode(manifest_content)
            packages = manifest_json.get("packages", [])
            allowed = tag.packages
            for pkg in packages:
                name = pkg.get("name")
                if not name:
                    continue
                if allowed and name not in allowed:
                    continue
                url = pkg.get("url", "")
                rev = pkg.get("rev", "")
                sub_dir = pkg.get("subDir")
                config_file = pkg.get("configFile", "")
                pkg_type = pkg.get("type", "git")
                if name not in repos:
                    repos[name] = {
                        "url": url,
                        "rev": rev,
                        "sub_dir": sub_dir,
                        "config_file": config_file,
                        "type": pkg_type,
                    }

    repo_names = []
    for name, info in repos.items():
        lake_package_repo(
            name = name,
            pkg_name = name,
            url = info["url"],
            commit = info["rev"],
            sub_dir = info["sub_dir"] or "",
            config_file = info["config_file"] or "",
            manifest_packages = list(repos.keys()),
        )
        repo_names.append(name)

    return mctx.extension_metadata(
        root_module_direct_deps = repo_names,
        root_module_direct_dev_deps = [],
    )

lake = module_extension(
    implementation = _lake_impl,
    tag_classes = {
        "manifest": _MANIFEST_TAG,
    },
)
