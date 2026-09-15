#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
#
# The one-satellite closure chain (STAPELN-R-32).
#
# stapeln compiles rokur's part descriptor -> emits a bundle -> the bundle
# builds -> rokur runs -> the gate answers honestly on BOTH arms -> tear down.
#
# This exists because every link in that chain was, at some point, green while
# broken. Each step below is therefore a GATE that exits non-zero, never a step
# that prints and continues:
#
#   1. the emitted stack.lock passes the same structural checks as the contract
#      test (mix stapeln.bundle --check);
#   2. the emitted rokur.toml is parsed by ROKUR'S OWN loader, not by a TOML
#      library that would accept a file rokur refuses -- the previous template
#      decoded as valid TOML and still made rokur refuse to start;
#   3. the image is built --no-cache, because a warm podman layer cache has
#      produced a false green here before;
#   4. the POSITIVE arm asserts /ready is 200, not merely that something is
#      listening;
#   5. the NEGATIVE arm withholds the secret and asserts /ready turns 503 while
#      /health stays 200 AND the container stays healthy. A smoke that only ever
#      sees the good case cannot tell a gate from a greeting.
#
# Usage:
#   ROKUR_SRC=/path/to/rokur/checkout backend/smoke/rokur-chain.sh
#
# Environment:
#   ROKUR_SRC  (required) a rokur checkout; its Containerfile is the build context
#   COMPOSE    compose provider            (default: docker-compose)
#   BUN        bun binary                  (default: bun)
#   MIX        mix binary                  (default: mix)
#   SMOKE_WORK work directory, reused      (default: ./tmp/rokur-chain)

set -euo pipefail

COMPOSE="${COMPOSE:-docker-compose}"
BUN="${BUN:-bun}"
MIX="${MIX:-mix}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND="$(dirname "$HERE")"
WORK="${SMOKE_WORK:-$BACKEND/tmp/rokur-chain}"
BUNDLE="$WORK/bundle"

FAILED=0
step()   { printf '\n== %s\n' "$1"; }
ok()     { printf '  ok   %s\n' "$1"; }
fail()   { printf '  FAIL %s\n' "$1"; FAILED=1; }
expect() { if [ "$2" = "$3" ]; then ok "$1 = $2"; else fail "$1 = $2, wanted $3"; fi; }
die()    { printf '\nABORT: %s\n' "$1" >&2; exit 1; }

cleanup() {
  if [ -f "$BUNDLE/compose.yaml" ]; then
    ( cd "$BUNDLE" && $COMPOSE -f compose.yaml -f compose.smoke.yaml down -v ) >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
step "preflight"
# ---------------------------------------------------------------------------
[ -n "${ROKUR_SRC:-}" ] || die "set ROKUR_SRC to a rokur checkout (the build context)."
[ -f "$ROKUR_SRC/Containerfile" ] || die "no Containerfile in ROKUR_SRC=$ROKUR_SRC"
[ -f "$ROKUR_SRC/config.js" ] || die "no config.js in ROKUR_SRC=$ROKUR_SRC (needed for gate 2)"
command -v "$BUN" >/dev/null || die "bun not found (set BUN=). curl and wget are absent from the runtime image, so bun is the probe."
command -v "$COMPOSE" >/dev/null || die "$COMPOSE not found (set COMPOSE=)"
command -v "$MIX" >/dev/null || die "mix not found (set MIX=)"
ok "rokur source, bun, $COMPOSE, mix"

mkdir -p "$BUNDLE"

# ---------------------------------------------------------------------------
step "1. stapeln compiles the descriptor and emits the bundle"
# ---------------------------------------------------------------------------
( cd "$BACKEND" && "$MIX" stapeln.bundle \
    --design "$HERE/rokur-only.design.json" --out "$BUNDLE" \
    --author "stapeln smoke" --email "smoke@example.invalid" \
    --license MPL-2.0 --owner metadatastician ) || die "bundle emission failed"
ok "bundle written to $BUNDLE"

# ---------------------------------------------------------------------------
step "2. GATE: the emitted stack.lock satisfies the contract"
# ---------------------------------------------------------------------------
( cd "$BACKEND" && "$MIX" stapeln.bundle --check "$BUNDLE/stack.lock" ) || die "stack.lock failed the contract check"

# ---------------------------------------------------------------------------
step "3. GATE: rokur's OWN loader accepts the emitted rokur.toml"
# ---------------------------------------------------------------------------
# Not a TOML library. rokur's parser is an ALLOWLIST -- an unknown table, an
# unknown key or a wrong type makes it refuse to start -- so only rokur's loader
# can answer whether the file stapeln emitted is loadable. The template this
# replaced was valid TOML and unloadable.
"$BUN" -e "
import { loadTomlFile } from '$ROKUR_SRC/config.js';
try {
  const cfg = loadTomlFile('$BUNDLE/rokur.toml');
  console.log('  ok   rokur loaded its own config:', JSON.stringify(cfg));
} catch (e) {
  console.error('  FAIL rokur REFUSED the emitted rokur.toml:', e.message);
  process.exit(1);
}
" || die "the emitted rokur.toml is not loadable by rokur"

# The published port comes from the emitted file, never from a literal here:
# a smoke that hardcodes the port cannot detect the drift it exists to catch.
PORT="$(sed -n 's/.*- "\([0-9][0-9]*\):[0-9][0-9]*\/tcp".*/\1/p' "$BUNDLE/compose.yaml" | head -1)"
[ -n "$PORT" ] || die "no published port found in the emitted compose.yaml"
ok "published port read from the emitted compose.yaml: $PORT"

# ---------------------------------------------------------------------------
step "4. materialise the build context and the operator's overlay"
# ---------------------------------------------------------------------------
mkdir -p "$BUNDLE/parts/rokur"
tar -C "$ROKUR_SRC" --exclude=node_modules --exclude=.git --exclude=test -cf - . \
  | tar -C "$BUNDLE/parts/rokur" -xf -
ok "rokur source copied into parts/rokur"

# rokur FAILS CLOSED: it reports ready only when every name in
# ROKUR_REQUIRED_SECRETS has a value under ROKUR_SECRET_<NAME>. That mapping is
# rokur's (main.js secretEnvName/1), not part of the secret's own name. The
# overlay is the OPERATOR's, which is why it is not in stapeln's descriptor:
# stapeln knows the stack's topology, never the deployment's secret names.
cat > "$BUNDLE/compose.smoke.yaml" <<'OVERLAY'
services:
  rokur:
    environment:
      - ROKUR_SECRET_SMOKE_GATE_TOKEN
OVERLAY
ok "operator overlay written"

# Per-run random, never printed.
export ROKUR_REQUIRED_SECRETS=SMOKE_GATE_TOKEN
ROKUR_API_TOKEN="$($BUN -e 'console.log(crypto.randomUUID())')"
export ROKUR_API_TOKEN

# ---------------------------------------------------------------------------
step "5. build --no-cache"
# ---------------------------------------------------------------------------
# --no-cache is not caution. A warm podman layer cache has served a stale image
# here and reported a green that the source could not have produced.
( cd "$BUNDLE" && $COMPOSE -f compose.yaml -f compose.smoke.yaml build --no-cache rokur ) \
  || die "image build failed"

# process.stdout.write, not console.log: bun COLOURISES a logged number, so
# `console.log(r.status)` returns an ANSI-wrapped "200" that no string
# comparison matches. Reading it by eye hides this completely -- the escape
# codes are invisible in a terminal and the number looks right. This smoke
# caught it on its first run, having been written against probes I had read by
# eye minutes earlier. Writing a string emits the bytes and nothing else.
probe() { "$BUN" -e "const r=await fetch('http://127.0.0.1:$PORT$1');process.stdout.write(String(r.status))"; }
body()  { "$BUN" -e "const r=await fetch('http://127.0.0.1:$PORT$1');process.stdout.write(await r.text())"; }

# ---------------------------------------------------------------------------
step "6. POSITIVE arm: the secret is supplied, the gate must OPEN"
# ---------------------------------------------------------------------------
ROKUR_SECRET_SMOKE_GATE_TOKEN="$($BUN -e 'console.log(crypto.randomUUID())')"
export ROKUR_SECRET_SMOKE_GATE_TOKEN
( cd "$BUNDLE" && $COMPOSE -f compose.yaml -f compose.smoke.yaml up -d --force-recreate --wait --wait-timeout 120 rokur ) \
  || die "the container never became healthy -- check the healthcheck argv actually reached the engine intact"

expect "/health" "$(probe /health)" "200"
expect "/ready"  "$(probe /ready)"  "200"
# A 404 on an undeclared path proves the listener is rokur and not something
# that answers 200 to everything, which is what a naive liveness probe accepts.
expect "/nope"   "$(probe /nope)"   "404"
READY_BODY="$(body /ready)"
case "$READY_BODY" in
  *'"code":"AUTHORIZED"'*) ok "/ready reports AUTHORIZED" ;;
  *) fail "/ready body was not AUTHORIZED: $READY_BODY" ;;
esac

# ---------------------------------------------------------------------------
step "7. NEGATIVE arm: the secret is withheld, the gate must CLOSE"
# ---------------------------------------------------------------------------
# The arm that makes this a gate. Liveness must stay green while readiness goes
# red: a 503 from /ready is an honest answer, not a dead process, and a probe
# that conflates them (the emitter once hardcoded `curl -fsS`) would restart a
# perfectly healthy gate for telling the truth.
unset ROKUR_SECRET_SMOKE_GATE_TOKEN
( cd "$BUNDLE" && $COMPOSE -f compose.yaml -f compose.smoke.yaml up -d --force-recreate --wait --wait-timeout 120 rokur ) \
  || die "the container did not become healthy with the secret withheld -- liveness must not depend on readiness"

expect "/health (secret withheld)" "$(probe /health)" "200"
expect "/ready  (secret withheld)" "$(probe /ready)"  "503"
NOT_READY_BODY="$(body /ready)"
case "$NOT_READY_BODY" in
  *'"code":"REQUIRED_SECRETS_MISSING"'*) ok "/ready reports REQUIRED_SECRETS_MISSING" ;;
  *) fail "/ready body was not REQUIRED_SECRETS_MISSING: $NOT_READY_BODY" ;;
esac

# ---------------------------------------------------------------------------
step "result"
# ---------------------------------------------------------------------------
if [ "$FAILED" -eq 0 ]; then
  printf '\nCHAIN GREEN: stapeln -> bundle -> build -> rokur runs -> gate opens AND closes.\n'
  exit 0
fi
printf '\nCHAIN RED: see the FAIL lines above.\n'
exit 1
