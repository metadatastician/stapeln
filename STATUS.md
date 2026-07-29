<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->
# Stapeln — Measured Status

**Last measured:** 2026-07-28  
**Honest completion:** ~45%  
**Languages:** ReScript (frontend) · Elixir/Phoenix (backend) · Zig (FFI) · Idris2 (ABI proofs)

> This document records **measured** state: every claim below is a file read, a build
> run, or a test executed on the dates shown. Where an existing document in this repo
> contradicts it, this one is correct and the other is stale. Full evidence and
> cross-repo context: `dev-notes/stapeln-ecosystem-COMPREHENSIVE-SITREP-2026-07-28.md`.

## Summary

~45% of code written; ~20% working end-to-end and defended by a gate.

## What genuinely works

- 41 REST routes + real Absinthe GraphQL (2 queries, 3 mutations), both funnelling through one `Stacks -> NativeBridge` boundary
- 10 UI tabs + 2 auth pages, all render and navigate (TEA pattern)
- 8 genuine Idris2 proofs — `%default total`, ZERO `believe_me`/`postulate`/`assert_total`/holes; `abi.ipkg` module list matches the directory (an honest ipkg, not the fake per-file `--check`)
- Real Ed25519 + SHA-256 in `ffi/zig/src/crypto.zig` via `std.crypto`, 10 tests
- Export/Import round-trips the full design via `DesignFormat.res` (components, connections, position, config)
- 339 real tests, ~6,200 lines (105 ExUnit, 107 Idris2, 110 Deno, 17 JS)

## What is broken, missing, or misreported

- **No CI gate runs any of the 339 tests.** `scripts/readiness-check.sh` is a correct 99-line gate (real builds, real tests, `exit 1` on failure) invoked by no Justfile target, workflow, or GitLab job.
- **Split-brain serializer.** Export-to-file uses `DesignFormat` and preserves topology; save-to-backend uses `App.res:47-64` hand-rolled string concat and DROPS connections, positions, and all config except `port`. A topology designer that does not persist its topology.
- **`App.res:99` + `:122`** call `Int.fromString` on a raw JSON body -> `None` -> `stackId = 0`; backend requires `id > 0`. Security scan and gap analysis fail 100% of the time. One line fixes both.
- Security Inspector and Gap Analysis have empty `init` and no-op handlers (`RunSecurityScan => state`); they make zero HTTP calls.
- `ABI-FFI-README.md` documents 7 `stapeln_*_json` functions implemented nowhere.
- `ffi/zig/src/bridge_cli.zig` — 353 real lines, 5 working ops, has NO build target.
- `container-stack/*` are 5 uninitialised submodules; the smoke workflow that 'checks' them has both build steps on `continue-on-error`.

## Notes and open rulings

- The README table (2026-02-13) UNDERSTATES six rows and OVERSTATES three. `TOPOLOGY.md` (~82%) is substantially false — it claims PostgreSQL at 100% when `mix.exs` has no `ecto`/`postgrex`, and claims the security/gap views call a real API when they make no calls at all.
- Contrary to the README, these exist and are substantial: miniKanren 834 lines, VeriSimDB 889, auth 722 (+2 UI pages), post-quantum 273.
- `frontend/lib/**` holds 188 committed build artefacts tracked despite `.gitignore` saying `lib/`; the '116 .res files / 44.5k lines' figure is really 56 files / ~19k lines.

## Next actions

1. Wire scripts/readiness-check.sh into CI — makes 339 existing tests load-bearing in one commit
2. Fix App.res:99 and :122 to parse data.id — unblocks security scan and gap analysis
3. Point SaveStack at DesignFormat.serializeDesign; widen the backend schema to carry connections
4. Adopt container/stapeln/ as the canonical output bundle and take ownership of its schema
5. Reconcile README / STATUS / TOPOLOGY into this single document
6. Untrack frontend/lib/** and delete ~1,108 lines of unreachable ReScript

## Ecosystem position

This repo is part of the six-repo container stack designed by `stapeln`. The canonical
integration contract is the 8-file `container/stapeln/` bundle, in which each satellite
consumes its own file:

| File | Consumer |
|---|---|
| `compose.toml` | selur |
| `vordr.toml` | vordr |
| `rokur.toml` | rokur |
| `.gatekeeper.yaml` | svalinn |
| `manifest.toml` + `ct-build.sh` | cerro-torre |
| `deploy.k9.ncl` | K9 / k9-svc |

Runtime chain: `svalinn (443/80) -> rokur (8081) -> app`, with vordr watching all three,
cerro-torre signing each as a `.ctp`, and selur as the network driver.

**As of this measurement no repo emits or consumes that bundle**; five mutually
incompatible ad-hoc contracts exist instead, of which exactly one works.

