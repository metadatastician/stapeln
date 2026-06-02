#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# affine-build.sh — compile every src/*.affine to dist/wasm/*.wasm.
#
# Requires the affinescript compiler. Set AFFINESCRIPT_BIN to its path, or
# put `affinescript` on PATH. In the container build this runs inside the
# wasm-build stage where the compiler is already installed (see Containerfile).
set -euo pipefail

BIN="${AFFINESCRIPT_BIN:-affinescript}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v "$BIN" >/dev/null 2>&1 && [[ ! -x "$BIN" ]]; then
  echo "affine-build: compiler not found (set AFFINESCRIPT_BIN)" >&2
  exit 1
fi

mkdir -p dist/wasm
find src -name '*.affine' -print0 | while IFS= read -r -d '' f; do
  base="$(basename "$f" .affine)"
  echo "compiling $f -> dist/wasm/${base}.wasm"
  "$BIN" compile "$f" -o "dist/wasm/${base}.wasm"
done
echo "affine-build: done"
