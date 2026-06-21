#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Reproduce + verify the AffineScript WASM cross-module constructor fix.
#
# Usage: repro.sh <path-to-affinescript-checkout>
#   Builds the compiler, then compiles a module that imports prelude's Option
#   constructors. Pre-fix this fails with Codegen.UnboundVariable "… Some";
#   post-fix (apply affinescript-wasm-ctor-link.patch) it compiles to WASM.
set -euo pipefail

AS="${1:?usage: repro.sh <path-to-affinescript-checkout>}"
cd "$AS"

echo "== build compiler =="
dune build bin/main.exe
BIN="./_build/default/bin/main.exe"
export AFFINESCRIPT_STDLIB="$AS/stdlib"

tmp="$(mktemp -d)"
cat > "$tmp/consumer.affine" <<'EOF'
module consumer;
use prelude::{Option, Some, None};
pub fn wrap(x: Int) -> Option<Int> { Some(x) }
pub fn empty() -> Option<Int> { None }
EOF

echo "== check (expect: Type checking passed) =="
"$BIN" check "$tmp/consumer.affine"

echo "== compile (pre-fix: UnboundVariable \"Some\"; post-fix: out.wasm) =="
"$BIN" compile "$tmp/consumer.affine"

echo "== full regression gate =="
dune runtest
