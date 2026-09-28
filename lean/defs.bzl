"""Public rules and helpers of rules_lean."""

load("//lean:toolchain.bzl", _LeanToolchainInfo = "LeanToolchainInfo", _TOOLCHAIN_TYPE = "TOOLCHAIN_TYPE", _lean_toolchain = "lean_toolchain")
load("//lean/private:lean_rules.bzl", _LeanLibraryInfo = "LeanLibraryInfo", _lean_axiom_test = "lean_axiom_test", _lean_binary = "lean_binary", _lean_library = "lean_library", _lean_negative_test = "lean_negative_test", _lean_prebuilt_library = "lean_prebuilt_library", _lean_test = "lean_test")

lean_toolchain = _lean_toolchain
lean_library = _lean_library
lean_prebuilt_library = _lean_prebuilt_library
lean_test = _lean_test
lean_binary = _lean_binary
lean_axiom_test = _lean_axiom_test
lean_negative_test = _lean_negative_test

LeanToolchainInfo = _LeanToolchainInfo
LeanLibraryInfo = _LeanLibraryInfo
TOOLCHAIN_TYPE = _TOOLCHAIN_TYPE
