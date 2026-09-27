#!/usr/bin/env bash
# Compile the Scheme interpreter, in dependency order, and run its executable
# checks. Exits non-zero on the first compile error or on a failed check.
#
# The Lean binary comes from LEAN_TOOLCHAIN (a toolchain directory) or from the
# `lean` of the PATH, which elan usually provides. The Bazel build of this
# project does not use this script; it uses the registered toolchain.
set -euo pipefail

if [ -n "${LEAN_TOOLCHAIN:-}" ]; then
  LEAN="$LEAN_TOOLCHAIN/bin/lean"
else
  LEAN="$(command -v lean || true)"
fi
if [ -z "$LEAN" ]; then
  echo "verify.sh: set LEAN_TOOLCHAIN, or put lean on the PATH" >&2
  exit 1
fi
OUT="${SCHEME_OLEANS:-/tmp/scheme-oleans}"

cd "$(dirname "$0")"

rm -rf "$OUT"
mkdir -p "$OUT/Scheme/Test"
export LEAN_PATH="$OUT"

modules=(
  Scheme/Token.lean
  Scheme/Lexer.lean
  Scheme/Sexp.lean
  Scheme/Parser.lean
  Scheme/Ast.lean
  Scheme/Env.lean
  Scheme/Prim.lean
  Scheme/Eval.lean
  Scheme/Test/Eval.lean
  Scheme/Repl.lean
  Scheme.lean
)

for m in "${modules[@]}"; do
  echo "compiling $m"
  "$LEAN" -o "$OUT/${m%.lean}.olean" "$m"
done

echo "running checks"
"$LEAN" --run Scheme/Test/Eval.lean
