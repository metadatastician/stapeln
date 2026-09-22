#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <6759885+hyperpolymath@users.noreply.github.com>
#
# Contract tests for the public badge claims in README.adoc and docs/BADGES.adoc.

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
readme="$repo_root/README.adoc"
register="$repo_root/docs/BADGES.adoc"

failures=0

pass() {
    printf '  PASS %s\n' "$1"
}

fail() {
    printf '  FAIL %s\n' "$1" >&2
    failures=$((failures + 1))
}

assert_contains() {
    local description=$1
    local pattern=$2
    local file=$3

    if grep -Eq -- "$pattern" "$file"; then
        pass "$description"
    else
        fail "$description"
    fi
}

assert_not_contains() {
    local description=$1
    local pattern=$2
    local file=$3

    if grep -Eq -- "$pattern" "$file"; then
        fail "$description"
    else
        pass "$description"
    fi
}

section_between() {
    local start=$1
    local end=$2
    local file=$3

    awk -v start="$start" -v end="$end" '
        $0 == start { in_section = 1 }
        in_section && $0 == end { exit }
        in_section { print }
    ' "$file"
}

printf '%s\n' '=== Badge Claim Contract Tests ==='

# The regression is broader than project 8509: no numeric registry project may
# be displayed until stapeln has a registration whose repo_url names this repo.
assert_not_contains \
    'README does not display an OpenSSF Best Practices registry badge' \
    '^image:.*bestpractices\.dev/projects/[0-9]+/badge' \
    "$readme"
assert_not_contains \
    'README does not link to the unrelated project 8509' \
    'bestpractices\.dev/projects/8509' \
    "$readme"
assert_contains \
    'README declares seven pending badges' \
    '^// Seven further badges are WANTED' \
    "$readme"
assert_contains \
    'README names OpenSSF Best Practices as pending restoration' \
    '^//.*OpenSSF Best Practices' \
    "$readme"

verified_section=$(section_between \
    '== Currently displayed and verified — keep' \
    '== Candidates worth adding' \
    "$register")
if [[ -z "$verified_section" ]]; then
    fail 'badge register retains the verified-badge section'
else
    pass 'badge register retains the verified-badge section'
fi
if grep -Fq 'OpenSSF Best Practices' <<<"$verified_section"; then
    fail 'verified-badge table excludes OpenSSF Best Practices'
else
    pass 'verified-badge table excludes OpenSSF Best Practices'
fi

false_claim_section=$(section_between \
    '== Removed as a false claim — 2026-09-22' \
    '== The standing rule' \
    "$register")
for evidence in \
    '=== 8. OpenSSF Best Practices' \
    'project *8509*' \
    'https://github.com/Isaiah0521/PA-updated-Weapon-Master' \
    'returns *zero* results' \
    '`stapeln`, `metadatastician` and `hyperpolymath`' \
    '*13' \
    'There is no registration to point at' \
    'https://www.bestpractices.dev/en/projects/new' \
    '<<the-standing-rule>>'; do
    if grep -Fq -- "$evidence" <<<"$false_claim_section"; then
        pass "false-claim record includes: $evidence"
    else
        fail "false-claim record includes: $evidence"
    fi
done

standing_rule=$(awk '
    $0 == "== The standing rule" { in_section = 1 }
    in_section { print }
' "$register")
for requirement in \
    'resolvable reference that names this project' \
    'resolving is not enough' \
    "jq -r .repo_url" \
    'https://github.com/metadatastician/stapeln'; do
    if grep -Fq -- "$requirement" <<<"$standing_rule"; then
        pass "standing rule includes: $requirement"
    else
        fail "standing rule includes: $requirement"
    fi
done

if (( failures > 0 )); then
    printf '\n%d badge claim contract test(s) failed\n' "$failures" >&2
    exit 1
fi

printf '\nAll badge claim contract tests passed\n'
