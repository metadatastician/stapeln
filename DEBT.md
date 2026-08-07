<!--
SPDX-License-Identifier: CC-BY-SA-4.0
SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)
-->

# Debt Register — stapeln

**Measured:** 2026-08-07 · **Commit:** `bc04e22` · **Method:** file reads, greps, `gh` API
queries and CI run history executed on that commit. Every claim below cites the command or
file that produced it. Where a claim could not be verified, it is marked **DIAGNOSIS
(unconfirmed)** rather than stated as fact.

> This is the single index of known debt. It supersedes nothing — the detailed registers it
> points at remain the source of truth for their domains:
> [`PROOF-NEEDS.md`](PROOF-NEEDS.md) · [`PROOF-BACKLOG.md`](PROOF-BACKLOG.md) ·
> [`TEST-NEEDS.md`](TEST-NEEDS.md) · [`docs/proof-debt.md`](docs/proof-debt.md) ·
> [`docs/tech-debt-2026-05-26.md`](docs/tech-debt-2026-05-26.md) ·
> [`.machine_readable/agent_instructions/debt.a2ml`](.machine_readable/agent_instructions/debt.a2ml).

**Severity scale.** `HIGH` = actively misleads a reader or lets a defect ship. `MEDIUM` =
real cost, no immediate blast radius. `LOW` = tidiness.

---

## Summary

| Domain | Items | Highest severity |
|---|---|---|
| [Licence](#1-licence-debt) | 3 | MEDIUM |
| [Documentation](#2-documentation-debt) | 6 | HIGH |
| [Code](#3-code-debt) | 5 | MEDIUM |
| [Proof](#4-proof-debt) | 2 | MEDIUM |
| [Test](#5-test-debt) | 4 | HIGH |
| [CI/CD](#6-cicd-debt) | 5 | HIGH |
| [Supply chain / security](#7-supply-chain--security-debt) | 2 | MEDIUM |

---

## 1. Licence debt

### L-1 · AGPL-3.0-or-later headers inside an MPL-2.0 repository — MEDIUM

Nine files declare `SPDX-License-Identifier: AGPL-3.0-or-later`. All nine are GitHub
metadata templates, none is source code:

```
.github/settings.yml
.github/ISSUE_TEMPLATE/{bug_report,config,custom,documentation,feature_request,question}.yml
.github/DISCUSSION_TEMPLATE/{ideas,q-and-a}.yml
```

Evidence: `grep -rl "SPDX-License-Identifier: AGPL-3.0-or-later" .` (excluding `LICENSES/`).
Repo-wide SPDX distribution is `482 MPL-2.0 · 178 CC-BY-SA-4.0 · 9 AGPL-3.0-or-later`.

The pattern (AGPL confined entirely to `.github/` scaffolding) is consistent with template
drift from an estate-wide sweep rather than a deliberate relicensing. AGPL is strong
copyleft; carrying it unremarked inside an MPL-2.0 project invites a licence-compatibility
question that nobody actually intended to raise.

**Next move:** confirm intent with the owner, then either relicense the nine files to
MPL-2.0 (expected) or document the mixed-licence arrangement explicitly in `LICENSE` and
`README.adoc`. Do not bulk-edit headers blind — see the estate rule that an SPDX identifier
must be moved, never imposed.

### L-2 · Two divergent copies of the MPL-2.0 text — LOW

`LICENSE` and `LICENSES/MPL-2.0.txt` are both 16,726-byte MPL-2.0 texts with **different
checksums** (`815ca599…` vs `f75d2927…`). Evidence: `md5sum LICENSE LICENSES/MPL-2.0.txt`.
Harmless today (GitHub's `/license` API correctly reports `MPL-2.0` from `LICENSE`), but two
diverging canonical texts is a REUSE-compliance trap.

**Next move:** make `LICENSES/MPL-2.0.txt` byte-identical to `LICENSE`, or make one a symlink.

### L-3 · `LICENSES/AGPL-3.0-or-later.txt` may be unused after L-1 — LOW

If L-1 resolves to "relicense the templates", the AGPL text becomes an orphan and REUSE will
flag an unused licence file.

**Next move:** delete it as part of the L-1 fix, not before.

---

## 2. Documentation debt

### D-1 · `README.adoc` status section is 6 months stale and contradicts reality — HIGH

`README.adoc:30` reads `== Current Status (as of 2026-02-13)` and `:32` claims
`**Honest completion: ~35%**`. The measured figure has been ~45% since 2026-07-28
([`STATUS.md`](STATUS.md)). The status table also states `Post-quantum crypto | Not started |
0%` (`README.adoc:55`) while ~273 lines of post-quantum code exist. Phase headings at
`:475`, `:492`, `:503` carry their own separate percentages.

This is the repo's front door and the first thing a reader trusts.

**Next move:** replace the embedded status table with a pointer to `STATUS.md` — one
measured document, not four drifting ones. (Addressed in this changeset.)

### D-2 · Unverifiable compliance badges — HIGH

`README.adoc:11-12` display `WCAG 2.3 AAA` and `Security: OWASP Compliant` badges. Both are
static `img.shields.io` badges — no audit artefact, no gate, and no date backs either claim.
`docs/ACCESSIBILITY-AUDIT-2026-03-29.adoc` exists but does not certify AAA.

A badge asserting a compliance level nothing verifies is precisely the "handwaving" the
project's own doctrine forbids.

**Next move:** remove both badges, or re-point them at a real, dated audit artefact.

### D-3 · Root-level documentation sprawl — MEDIUM

43 Markdown/AsciiDoc files sat at repository root. Evidence: `ls -1 *.md *.adoc | wc -l`.
Two were session artefacts rather than project documentation
(`SESSION-SUMMARY-2026-02-05.md`, `SESSION-PICKUP-2026-03-21.md`); **both moved to
`docs/sessions/` in this changeset**, joining the three already there.

41 root documents remain. The residue is genuine sprawl — nine separate security/verification
documents (`ATTACK-SURFACE-GAPS`, `OBVIOUS-VULNERABILITIES`, `RED-TEAM-EXERCISE`,
`SECURITY-STACK-AUDIT`, `SECURITY-REASONING-ENGINE`, `VERIFICATION-SPEC`, `REKOR`,
`PROOF-NEEDS`, `PROOF-BACKLOG`) with no index between them.

**Next move:** keep the root to what a newcomer or a tool looks for (README, LICENSE,
SECURITY, CONTRIBUTING, CODE_OF_CONDUCT, GOVERNANCE, CHANGELOG, STATUS, DEBT, ROADMAP) and
move the rest under `docs/` with an index. Not done here: moving nine linked files needs a
link-rewrite pass, which deserves its own reviewable change.

### D-4 · Duplicate ROADMAP — LOW

`ROADMAP.md` (208 lines, substantive) and `ROADMAP.adoc` (12 lines) coexist. The `.adoc` is
self-declared `= stapeln Roadmap Alias (Deprecated)`, so this is documented, not silent —
but it still means two files answer to one name.

Checked in this changeset: `docs/READINESS.adoc:156` and `:172` both link to `ROADMAP.adoc`,
so it is **not** yet safe to delete.

**Next move:** repoint `docs/READINESS.adoc` at `ROADMAP.md`, then delete the alias.

### D-5 · The wiki is empty — MEDIUM

The GitHub wiki is enabled and contains exactly one page: `Home.md`, 29 bytes, reading
"Welcome to the stapeln wiki!" (commit `54904fa`, "Initial Home page"). An enabled-but-empty
wiki is a dead end for anyone who clicks it.

**Next move:** populate it as the *navigational* layer over the in-repo docs — or disable it.
(Populated in this changeset.)

### D-6 · `ABI-FFI-README.md` documents functions that do not exist — MEDIUM

Seven `stapeln_*_json` functions are documented with no implementation anywhere in the tree.
Carried from the 2026-07-28 audit; re-confirm before acting.

**Next move:** mark the section "planned", or implement. Not both silent.

---

## 3. Code debt

### C-1 · `stack_channel.ex` changes shipped with zero test coverage — MEDIUM

PR #17 (merged 2026-08-04) added `to_stack_map/1` and a `%{services: ...}` re-wrap to
`backend/lib/stapeln_web/channels/stack_channel.ex`. There is no
`backend/test/stapeln_web/channels/` directory and no `ChannelCase` in `test/support/`, so
the WebSocket path — including the "legacy raw-services shape keeps working" back-compat
requirement — is argued but not demonstrated. Raised in review before merge; not addressed.

**Next move:** add `ChannelCase` + `stack_channel_test.exs` covering design-doc string
payload, legacy services-map payload, and a malformed payload.

### C-2 · `ApiDecode` accepts a non-positive id — LOW

`frontend/src/ApiDecode.res` maps `data.id` through `Float.toInt` without a `> 0` guard. The
backend never emits `0`, so "no path yields `stackId = 0`" is currently incidental rather
than structural — and `stackId = 0` was the exact defect PR #17 existed to kill.

**Next move:** guard `n > 0` and integral; add the `id: 0 → Error` test case.

### C-3 · Frontend test placed in an invented tree — LOW

`frontend/tests/unit/api_decode_test.js` was added alongside an already-existing root-level
`tests/unit/`. Two unit-test roots, and no runner covers the new one.

**Next move:** move it to `tests/unit/`.

### C-4 · `bridge_cli.zig` has no build target — MEDIUM

353 lines, 5 working operations, unreachable from any build. Carried from 2026-07-28.

**Next move:** add the build target or move the file out of `src/`.

### C-5 · Committed build artefacts — LOW

`frontend/lib/**` holds build output tracked in git despite `.gitignore` listing `lib/`.
Compiled `.res.js` files are *deliberately* committed (the repo has no build step in CI), so
this needs an explicit ruling rather than a blind `git rm`.

**Next move:** rule on it, then make `.gitignore` and reality agree.

---

## 4. Proof debt

### P-1 · Proof coverage is narrow but honest — MEDIUM

8 Idris2 proof modules exist under `src/abi/` with `%default total` and **zero**
`believe_me` / `postulate` / `assert_total` / holes — genuinely honest proofs, unusual in
this estate. The debt is scope, not integrity: they cover the ABI layer only.

Detail lives in [`PROOF-NEEDS.md`](PROOF-NEEDS.md) (324 lines) and
[`PROOF-BACKLOG.md`](PROOF-BACKLOG.md) (148 lines).

**Next move:** none urgent. Keep the honesty property under gate (see T-2).

### P-2 · No gate proves the proofs still check — MEDIUM

`stapeln-tests.ipkg` exists, but no workflow runs an Idris2 build. A proof nothing re-checks
decays silently.

**Next move:** add an `idris2 --build` step; ensure it can fail (per estate rule, per-file
`--check` is a fake gate — use the `.ipkg`).

---

## 5. Test debt

### T-1 · `scripts/readiness-check.sh` is invoked by nothing — HIGH

A correct 5-gate script (clean tree, lockfile hygiene, Deno tests, `rescript build`,
`mix deps.get && mix test`) that exits non-zero on failure. Evidence:
`grep -rln readiness-check .github/workflows/ Justfile .gitlab-ci.yml` → **no matches**.

The single highest-leverage fix in the repo: one caller makes the whole suite load-bearing.

**Next move:** `just readiness` + a workflow job. (Planned as campaign Task 3.)

### T-2 · `mix test` runs on GitLab only — HIGH

122 ExUnit tests across 15 files. `mix test` appears in `.gitlab-ci.yml:144` and in **no**
GitHub workflow. GitHub Actions is the forge that gates merges here.

**Next move:** add a `Backend Tests` workflow.

### T-3 · Two of three Deno suites are soft-gated — MEDIUM

- `.github/workflows/e2e.yml:20` — e2e suite, `|| echo "::warning::…"`. **Honest**: genuinely
  needs Podman.
- `.github/workflows/e2e.yml:43` — aspect suite, `|| echo "Aspect test script not found"`.
  **Dishonest**: `tests/aspect/aspect_tests.sh` exists, so the fallback can only mask real
  failures.
- Property suite (42 tests) is hard-gated. Good.

**Next move:** drop the `|| echo` from the aspect step; leave e2e soft and say why.

### T-4 · The published test count is not reproducible — MEDIUM

`STATUS.md` (2026-07-28) claims *"339 real tests (105 ExUnit, 107 Idris2, 110 Deno, 17 JS)"*.
Measured on `bc04e22`:

| Suite | Count | Method |
|---|---|---|
| ExUnit | **122** in 15 files | `grep -rhoE '^\s*(test\|property) "' backend/test` |
| Deno/JS | **107** in 6 files | `grep -rhoE 'Deno\.test\(' tests` |
| Zig | **16** | `grep -rhoE '^\s*test "' ffi/zig` |
| Idris2 | 8 modules, **1** named `test*` binding | `grep -rhoE '^\s*test[A-Za-z0-9_]* :' tests/idris2` |

ExUnit grew 105 → 122 (PR #17 added tests, as claimed). The **107 Idris2 tests** figure is
the one that does not reproduce by any method tried: the Idris2 suite is 8 modules driven by
a custom `Test/Spec.idr` harness, and discrete cases are not enumerable by grep.

A defensible headline is **245 executable test cases** (122 + 107 + 16) plus 8 Idris2 proof
modules — not 339. This is a *measurement-methodology* discrepancy, not an accusation of
fabrication, but the repo should publish a number a reader can reproduce.

**Next move:** publish the per-suite table with its commands (done in `STATUS.md` here).

---

## 6. CI/CD debt

### CI-1 · OSSF Scorecard has `startup_failure`d every day since at least 2026-08-04 — HIGH

Four consecutive daily runs, all `startup_failure`, all 0s. Evidence:
`gh run list --workflow scorecard.yml`.

**DIAGNOSIS (unconfirmed):** `.github/workflows/scorecard.yml` declares workflow-level
`permissions:` including `actions: read`, but the `scorecard` job — which is a `uses:` call
to `hyperpolymath/standards/.github/workflows/scorecard-reusable.yml@bd0df9ea…` — re-declares
its own `permissions:` block **omitting `actions: read`**. A job-level block replaces the
workflow-level one; if the reusable workflow requests `actions: read`, the call is a
permission escalation and GitHub rejects the workflow before any job runs. This matches a
known estate failure pattern.

Note the failure mode: a parse/permission rejection produces a run with **zero jobs**, which
`gh pr checks` does not surface as a failing check. It is invisible unless you look at run
history.

**Next move:** test the hypothesis by adding `actions: read` to the job-level block. If that
does not fix it, resolve the reusable's declared permissions against the caller's.

### CI-2 · Three workflows are red on `main` — HIGH

As of the 2026-08-04 push: `Secret Scanner` **failure**, `Governance` **failure**,
`Instant Sync` **failure**. (`Hypatia Security Scan`, `SPARK Theatre Gate`, `BoJ Server Build
Trigger` pass.) Open PRs #20–#24 appear to be addressing the first two.

**Next move:** land #20–#24, then re-measure. Red `main` normalises red.

### CI-3 · `container-stack-smoke.yml` cannot fail — MEDIUM

Both build steps carry `continue-on-error: true` (`:53`, `:59`), over five uninitialised
submodules. A gate that cannot fail is not a gate.

**Next move:** initialise the submodules and remove `continue-on-error`, or delete the
workflow and stop advertising a check that checks nothing.

### CI-4 · `boj-build.yml` step is `continue-on-error` — LOW

`:19`. Same class as CI-3, lower stakes.

### CI-5 · GitLab is the only place the backend is tested — MEDIUM

See T-2. Also `.gitlab-ci.yml` has three `allow_failure: true` jobs (`:43`, `:64`, `:77`)
against two hard ones (`:29`, `:36`).

**Next move:** treat GitHub as the gate of record; mirror the hard jobs there.

---

## 7. Supply chain / security debt

### S-1 · Gitleaks reports 12 findings on `main` — MEDIUM

The `scan / gitleaks` job fails with `leaks found: 12`. Open PRs #20 and #21 assert all
twelve are test fixtures and propose an allowlist.

**Next move:** land the allowlist **only** after each of the twelve is individually
confirmed a fixture. An allowlist applied without that check converts a real gate into a
fake one. Note the estate rule: gitleaks' allowlist pattern `(doc|docx)$` substring-matches
`.adoc` — verify the allowlist does not blind the scanner to whole file types.

### S-2 · Five uninitialised submodules under `container-stack/` — MEDIUM

`container-stack/{cerro-torre,rokur,selur,svalinn,vordr}` are submodule stubs. The smoke
workflow "checking" them cannot fail (CI-3). Consumers cannot build the container path.

**Next move:** initialise, or vendor the interfaces, or remove and depend on the published
artefacts.

---

## Cross-cutting note: the honest-red principle

Several items above (T-3, CI-3, CI-4) share one shape: **a gate wired so it cannot fail.**
The project's own doctrine is that a proof gate must be able to fail, and that an honest red
beats a fake green. Fixing these will make the board *look worse* and *be* better. That is
the intended direction.

---

## Related

- [`STATUS.md`](STATUS.md) — measured state, same commit
- [`.machine_readable/6a2/STATE.a2ml`](.machine_readable/6a2/STATE.a2ml) — machine mirror
- [`ROADMAP.md`](ROADMAP.md) — intended direction
- [`SECURITY.md`](SECURITY.md) — disclosure policy
