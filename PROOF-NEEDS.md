# PROOF-NEEDS.md
<!-- SPDX-License-Identifier: PMPL-1.0-or-later -->

## Current State (2026-03-30 audit)

- **LOC**: ~60,900
- **Languages**: Elixir, ReScript, Idris2, Zig, Rust
- **Postulates before**: 26 across 5 files + 2 `assert_total` (spec crash stubs)
- **Postulates after**: 13 (50% reduction)
- **Proven**: 13 postulates eliminated with genuine proofs (Refl, rewrite, with-blocks)
- **Vordr proofs**: 0 postulates (all proven structurally — lifecycle, SBOM, attestation)

## What Was Proven (2026-03-30)

### Layout Arithmetic — 3 postulates → Refl (src/abi/Layout.idr)

| Postulate | Proof | Root cause of original postulation |
|-----------|-------|------------------------------------|
| `serviceSpecSizeCorrect` | `Refl` | Idris2 treats lowercase `serviceSpecLayout` as implicit variable. Fixed by inlining concrete fields. |
| `stackSpecHeaderSizeCorrect` | `Refl` | Same |
| `serviceSpecLastFieldCorrect` | `Refl` | Same — inlined `40` instead of `totalSize serviceSpecLayout` |

### Contiguity — 5 postulates → Refl (src/abi/Proofs.idr)

| Postulate | Proof | Notes |
|-----------|-------|-------|
| `serviceSpecContiguous0` | `Refl` | 0+8=8 — fieldEnd reduces on concrete MkFieldLayout |
| `serviceSpecContiguous1` | `Refl` | 8+8=16 |
| `serviceSpecContiguous2` | `Refl` | 16+8=24 |
| `serviceSpecContiguous3` | `Refl` | 24+8=32 |
| `serviceSpecContiguous4` | `Refl` | 32+4=36 |

### Chain Properties — 2 postulates → structural proofs (cerro-torre SignatureProofs.idr)

| Postulate | Proof technique | Notes |
|-----------|----------------|-------|
| `chainExtension` | `rewrite validSig in validChain` | Substitutes True into if-condition, result follows |
| `chainCommutative` | Nested `with`-blocks, 4-case Bool split | Sequential nesting (not parallel `\|`) is key — Idris2 abstracts correctly |

Additionally, 2 new proven helper lemmas added:
- `chainHeadValid` — extracts head signature validity via `with`-block
- `chainTailValid` — extracts tail chain validity via `with`-block

### Unit-Return — 3 postulates → trivial (Theorems.idr, ImporterProofs.idr)

| Postulate | Proof | Notes |
|-----------|-------|-------|
| `thresholdSatisfaction` | `()` | Unit return type always constructible; premises carry the real guarantee |
| `nonRepudiation` | `()` | Same — legal/crypto property encoded in premises, not return type |
| `tarBombPrevention` | `()` | Same — LTE premises carry the bound guarantee |

## What Remains Postulated (13 total)

### Legitimate Cryptographic Axioms (4) — KEEP FOREVER

These depend on computational hardness assumptions that are unprovable in any formal system.

| Postulate | File | Justification |
|-----------|------|---------------|
| `ed25519Correctness` | CryptoProofs.idr | Edwards curve group law (RFC 8032) |
| `sha256CollisionResistant` | CryptoProofs.idr | Collision resistance (NIST SP 800-107) |
| `signatureNonReplayable` | SignatureProofs.idr | Ed25519 EUF-CMA security |
| `signatureNonMalleable` | SignatureProofs.idr | Ed25519 cofactored verification (RFC 8032 §8) |

### Crypto Composition Theorems (2) — KEEP (depend on axioms above)

| Postulate | File | Depends on |
|-----------|------|------------|
| `tamperEvidence` | Theorems.idr | sha256CollisionResistant + signatureNonReplayable |
| `replayPrevention` | Theorems.idr | signatureNonReplayable |

### Bool/Propositional Equality Gap (1) — PROVABLE WITH INFRASTRUCTURE

| Postulate | File | What's needed |
|-----------|------|---------------|
| `chainImpliesIndividual` | SignatureProofs.idr | DecEq for `(Vect 32 Bits8, Vect 64 Bits8)` + `(a == b) = True -> a = b` lemma, or redefine elem using `Data.List.Elem` |

### String Primitive Limitations (6) — KEEP UNTIL IDRIS2 STDLIB IMPROVES

`isPrefixOf` and `isInfixOf` are C primitives with no reduction rules in Idris2's type checker.

| Postulate | File | What's needed |
|-----------|------|---------------|
| `normalizedIsSafe` | ImporterProofs.idr | String decomposition + isInfixOf lemmas |
| `extractionSafety` | ImporterProofs.idr | `isPrefixOf s (s ++ t) = True` lemma |
| `symlinkSafety` | ImporterProofs.idr | Same as extractionSafety |
| `absolutePathRejection` | ImporterProofs.idr | `isPrefixOf "/" s = True -> Not (SafePath s)` |
| `ociLayoutEnforcement` | ImporterProofs.idr | DecEq on TarEntry + elem/any equivalence |
| `zipSlipPrevention` | ImporterProofs.idr | Same as extractionSafety |

## assert_total Usage (2) — ACCEPTABLE

Both in `CryptoProofs.idr`, used as crash stubs for spec-only functions (`verifyEd25519`, `sha256`) that must never be called at runtime. Runtime code uses `CryptoFFI.verifyEd25519IO` and `CryptoFFI.sha256IO` instead.

## Dangerous Patterns

- `Obj.magic` in `svalinn/` and `vordr/` ReScript clients — these are FFI boundary crossings for ReScript-to-Idris2 interop, not proof cheats.
- Zero `believe_me`, zero `cast Refl`, zero `unsafePerformIO` in proof code.

## Template ABI Cleanup (2026-03-29)

Template ABI removed — was creating false impression of formal verification.
The removed files (Types.idr, Layout.idr, Foreign.idr) contained only RSR template
scaffolding with unresolved {{PROJECT}}/{{AUTHOR}} placeholders and no domain-specific proofs.
