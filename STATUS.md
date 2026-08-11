<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->
# Stapeln — Measured Status

**Last measured:** 2026-08-07 · **Commit:** `bc04e22`
**Honest completion:** ~48%
**Languages:** ReScript/React (frontend) · Elixir/Phoenix (backend) · Zig (FFI) · Idris2 (ABI proofs)

> This document records **measured** state: every claim is a file read, a command run, or a
> CI query executed at the commit above. Where another document in this repo contradicts it,
> this one is correct and the other is stale. Known debt is indexed in [`DEBT.md`](DEBT.md).

## What stapeln is

A **compiler from a visual topology to a verified deployment bundle**. You compose a
container stack on a drag-and-drop canvas; stapeln validates the topology, scans it for
security gaps, and lowers it to deployment artefacts. The design document round-trips
losslessly, so the canvas — not the generated files — is the source of truth.

It is the designer for a six-repo ecosystem: **selur** (compose orchestration), **vordr**
(health/crash watching), **rokur** (secrets gate), **svalinn** (edge policy gateway),
**cerro-torre** (signing and provenance).

## What genuinely works

- 41 REST routes + Absinthe GraphQL (2 queries, 3 mutations), both funnelling through one
  `Stacks → NativeBridge` boundary
- 10 UI tabs + 2 auth pages, all render and navigate (TEA / Elm architecture)
- **Full-fidelity design persistence** — save, autosave, WebSocket validate, security scan
  and gap analysis all serialise through `DesignFormat.res`, preserving components,
  connections, positions and config *(fixed in #17, 2026-08-04)*
- **Security scan and gap analysis reach the backend** — `saveStack` decodes `data.id` into a
  typed `result<int, string>`; the `stackId = 0` defect that made both endpoints return 400
  on every call is gone *(fixed in #17)*
- 8 Idris2 ABI proof modules with `%default total` and **zero** `believe_me` / `postulate` /
  `assert_total` / holes; `abi.ipkg`'s module list matches the directory (an honest package
  build, not a per-file `--check` fake gate)
- Real Ed25519 + SHA-256 in `ffi/zig/src/crypto.zig` via `std.crypto`, 16 Zig tests
- Multi-format code generation: `Codegen.generate_all/1` and `PipelineCodegen`'s six emitters
  (Containerfile, selur-compose, podman-compose, k8s, Helm, OCI bundle), exposed at
  `POST /api/stacks/:id/generate`
- GitHub Actions runs again — the dependency-lockfile remediation landed in #16/#18, ending
  the estate-wide `startup_failure` outage for this repo

## Test inventory

Counted at `bc04e22`. Commands are given so the numbers are reproducible.

| Suite | Cases | Files | Command |
|---|---|---|---|
| Elixir ExUnit | **122** | 15 | `grep -rhoE '^\s*(test\|property) "' backend/test` |
| Deno / JS | **107** | 6 | `grep -rhoE 'Deno\.test\(' tests` |
| Zig | **16** | — | `grep -rhoE '^\s*test "' ffi/zig` |
| Idris2 | 8 proof modules | 8 | custom `Test/Spec.idr` harness — cases not grep-enumerable |

**245 executable test cases** plus 8 Idris2 proof modules. An earlier figure of "339 tests"
circulated; its Idris2 component (107) does not reproduce by any method tried — see
[`DEBT.md` T-4](DEBT.md#t-4--the-published-test-count-is-not-reproducible).

## What is broken, missing, or misreported

- **`scripts/readiness-check.sh` is invoked by nothing.** A correct 5-gate script — clean
  tree, lockfile hygiene, Deno tests, `rescript build`, `mix deps.get && mix test` — wired to
  no Justfile target, workflow, or GitLab job. One caller would make the whole suite
  load-bearing.
- **No GitHub workflow runs `mix test`.** The 122 backend tests gate nothing on the forge
  that gates merges. `mix test` appears only in `.gitlab-ci.yml:144`.
- **The aspect test step cannot fail** — `e2e.yml:43` ends `|| echo "Aspect test script not
  found"`, but the script exists, so the fallback can only mask real failures. (The e2e step's
  soft gate at `:20` is honest: it genuinely needs Podman.)
- **OSSF Scorecard has `startup_failure`d daily since at least 2026-08-04** — a run with zero
  jobs, which `gh pr checks` does not surface as failing.
- **`Secret Scanner`, `Governance` and `Instant Sync` are red on `main`.** Open PRs #20–#24
  address the first two.
- **`container-stack/` holds five uninitialised submodules**, and the smoke workflow that
  "checks" them has both build steps on `continue-on-error`.
- **`ABI-FFI-README.md` documents 7 `stapeln_*_json` functions implemented nowhere.**
- **`ffi/zig/src/bridge_cli.zig`** — 353 real lines, 5 working ops, no build target.
- **The WebSocket channel path has no tests** — `stack_channel.ex` changed in #17 with no
  `ChannelCase` and no channel test directory.
- **`README.adoc`'s status section is dated 2026-02-13** and disagrees with this document;
  its `WCAG 2.3 AAA` and `OWASP Compliant` badges are backed by no audit artefact or gate.

## Next actions

Ordered by leverage.

1. Wire `scripts/readiness-check.sh` into `just` and CI — makes 245 tests load-bearing in one
   commit
2. Add a GitHub `Backend Tests` workflow running `mix test`
3. Drop the dishonest `|| echo` from the aspect step
4. Fix the Scorecard `startup_failure` (see [`DEBT.md` CI-1](DEBT.md#ci-1--ossf-scorecard-has-startup_failured-every-day-since-at-least-2026-08-04))
5. Add channel tests for the WebSocket path shipped in #17
6. Adopt `container/stapeln/` as the canonical output bundle and take ownership of its schema
   — the compiler ruling
7. Resolve the AGPL headers on `.github/` templates

## CI/CD status

**Actions is live again** (post-#16/#18 lockfile adoption); the estate-wide `startup_failure`
outage no longer applies to this repo. As of the 2026-08-04 push on `main`:

- **Passing:** Hypatia Security Scan, SPARK Theatre Gate, BoJ Server Build Trigger
- **Failing:** Secret Scanner (gitleaks: 12 findings), Governance, Instant Sync
- **`startup_failure`:** OSSF Scorecard (daily, recurring)

**Gates that genuinely enforce something:** the Deno property suite (42 tests, hard-gated at
`e2e.yml:31`), GitLab `trivy` and `gitleaks` (`allow_failure: false`), Hypatia, and the SPARK
Theatre Gate.

## Related

- [`DEBT.md`](DEBT.md) — full debt register, same commit
- [`.machine_readable/6a2/STATE.a2ml`](.machine_readable/6a2/STATE.a2ml) — machine mirror
- [`ARCHITECTURE.md`](ARCHITECTURE.md) · [`TOPOLOGY.md`](TOPOLOGY.md) · [`ROADMAP.md`](ROADMAP.md)
