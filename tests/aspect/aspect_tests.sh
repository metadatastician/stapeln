#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# tests/aspect/aspect_tests.sh — Aspect tests for stapeln.
#
# Validates cross-cutting concerns:
#   1. SPDX licence headers on all source files
#   2. No hardcoded secrets or credentials
#   3. HTTPS-only URLs in config and source
#   4. Containerfile uses Chainguard base image
#   5. No banned package managers (npm, bun, yarn)
#   6. Aspect security test passes via Deno

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASSED=0
FAILED=0

check() {
    local desc="$1"
    local result="$2"
    if [ "$result" = "0" ]; then
        echo -e "  ${GREEN}PASS${NC} $desc"
        PASSED=$((PASSED + 1))
    else
        echo -e "  ${RED}FAIL${NC} $desc"
        FAILED=$((FAILED + 1))
    fi
}

echo "=== Stapeln Aspect Tests ==="
echo ""

# 1. SPDX headers
missing_spdx=$(find src/ -name '*.ts' -o -name '*.js' -o -name '*.rs' 2>/dev/null \
    | xargs -r grep -rL "SPDX-License-Identifier" 2>/dev/null | wc -l)
check "SPDX headers present on source files" "$([ "$missing_spdx" -eq 0 ] && echo 0 || echo 1)"

# 2. No hardcoded secrets (basic check)
secret_hits=$(grep -rn 'password\s*=\s*["'"'"'][^"'"'"']\|secret\s*=\s*["'"'"'][^"'"'"'\|api_key\s*=\s*["'"'"'][^"'"'"'' \
    src/ 2>/dev/null | grep -iv 'test\|example\|placeholder\|TODO' | wc -l || true)
check "No hardcoded secrets in source" "$([ "$secret_hits" -eq 0 ] && echo 0 || echo 1)"

# 3. HTTPS-only URLs
http_hits=$(grep -rn 'http://[^l]' src/ 2>/dev/null | grep -v '# ' | wc -l || true)
check "HTTPS-only URLs (no plain http://)" "$([ "$http_hits" -eq 0 ] && echo 0 || echo 1)"

# 4. Chainguard base image in Containerfile
if [ -f Containerfile ]; then
    chainguard=$(grep -c 'cgr.dev/chainguard' Containerfile 2>/dev/null || true)
    check "Containerfile uses Chainguard base image" "$([ "$chainguard" -gt 0 ] && echo 0 || echo 1)"
else
    echo -e "  ${YELLOW}SKIP${NC} Containerfile check — no Containerfile found"
fi

# 5. No banned package managers
banned_pm=$(grep -rn '"scripts"' package.json 2>/dev/null | head -1 | wc -l || true)
check "No npm/bun/yarn package scripts present" "$([ "$banned_pm" -eq 0 ] && echo 0 || echo 1)"

# 6. Security aspect test via Deno
if command -v deno >/dev/null 2>&1 && [ -f tests/aspect/security_test.ts ]; then
    deno test tests/aspect/security_test.ts --allow-all --no-check >/dev/null 2>&1
    check "Deno security aspect test passes" "$?"
else
    echo -e "  ${YELLOW}SKIP${NC} Deno security test — deno not found or test missing"
fi

echo ""
echo "=== Results: ${PASSED} passed, ${FAILED} failed ==="
[ "$FAILED" -eq 0 ]
