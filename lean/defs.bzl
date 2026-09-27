"""Public rules and helpers of rules_lean."""

load("//lean:toolchain.bzl", _TOOLCHAIN_TYPE = "TOOLCHAIN_TYPE", _LeanToolchainInfo = "LeanToolchainInfo", _lean_toolchain = "lean_toolchain")
load("//lean/private:lean_rules.bzl", _LeanLibraryInfo = "LeanLibraryInfo", _lean_library = "lean_library", _lean_test = "lean_test")

lean_toolchain = _lean_toolchain
lean_library = _lean_library
lean_test = _lean_test

LeanToolchainInfo = _LeanToolchainInfo
LeanLibraryInfo = _LeanLibraryInfo
TOOLCHAIN_TYPE = _TOOLCHAIN_TYPE
