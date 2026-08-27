<!--
SPDX-License-Identifier: CC-BY-SA-4.0
SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)
-->

# Changelog

All notable changes to `stapeln` will be documented in this file.

This file is generated from conventional commits by the
[`changelog-reusable.yml`](https://github.com/hyperpolymath/standards/blob/main/.github/workflows/changelog-reusable.yml)
workflow (`hyperpolymath/standards#206`). Adopt the workflow in this repo's CI to keep this file in sync automatically — see
[`templates/cliff.toml`](https://github.com/hyperpolymath/standards/blob/main/templates/cliff.toml)
for the canonical config.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
this project aims to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- feat(svalinn): ReScript→AffineScript/typed-wasm migration (phase 1) (#46)
- feat(launcher): migrate to launch-scaffolder (server-url, port 4010)
- feat: cross-platform launcher, product vision doc, manifest disambiguation
- feat(crg): add crg-grade and crg-badge justfile recipes
- feat: add Phase 3 simulation engine — build sim, what-if, supply chain
- feat: JWT refresh tokens — access/refresh pair, refresh endpoint
- feat: migrate cerro-torre MVP tools from Python to Julia

### Fixed

- fix(licence): clear scaffold-placeholder leak (Tranche 3) (#55)
- fix(cerro-torre): String-bridge — discharge 3 ImporterProofs postulates (#53)
- fix(cerro-torre): prove chainCommutative — resolve 2026-04-19 regression (#52)
- fix(affine): migrate record literals to #{ } (affinescript#218) (#54)
- fix(ci): sync hypatia-scan.yml to canonical (kill cd-scanner build drift) (#51)
- fix: vordr 1.86 builder + repair A2ML/trufflehog/Hypatia CI checks (#41)
- fix(cerro-torre): make the full Ada container build compile end-to-end (#42)
- fix(svalinn): repair ReScript build + stabilise pre-existing CI checks (#40)
- fix(container-stack): repair clean-build breakages + add podman smoke CI (#37)
- fix(ci): move secret-scanner Cargo.toml gate from job-level if: to step-level (#36)

### Documentation

- docs: add implementation-subtree READMEs and READINESS file (CRG D→C)
- docs(stapeln): add Haiku/Sonnet/Opus session briefs for todo execution
- docs(cerro-torre): record chainCommutative regression + 2026-04-19 proof-build-restored pass
- docs: update TEST-NEEDS.adoc with session 9 test additions
- docs: add M2 estate audit report (2026-04-04)
- docs: substantive CRG C annotation (EXPLAINME.adoc)
- docs: update STATE with 2026-04-03 session work
- docs: document ed25519Correctness type signature weakness
- docs: add BibTeX bibliography for logic-driven container security paper

### CI

- ci(gitignore): ignore generated/* artefacts (Refs standards#93) (#60)
- ci(spark): adopt estate SPARK Theatre Gate (standards#135) (#57)
- ci(proof): add GitHub formal-verification gate for cerro-torre (#56)
- ci: re-adopt hyperpolymath/a2ml-validate-action (Closes #44) (#50)
- ci: fix three repo-wide failing checks at the root (A2ML, trufflehog, Hypatia) (#43)

## Pre-history

Prior commits to this file's introduction are recorded in git history but not formally classified into Keep-a-Changelog sections. To backfill, run `git cliff -o CHANGELOG.md` locally using the canonical [`cliff.toml`](https://github.com/hyperpolymath/standards/blob/main/templates/cliff.toml) — this is one-shot mechanical work.

---

<!-- This file was seeded by the 2026-05-26 estate tech-debt audit follow-up (Row-2 Phase 3); see [`hyperpolymath/standards/docs/audits/2026-05-26-estate-documentation-debt.md`](https://github.com/hyperpolymath/standards/blob/main/docs/audits/2026-05-26-estate-documentation-debt.md). -->
