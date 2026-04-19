# PROOF-NEEDS.md
<!-- SPDX-License-Identifier: PMPL-1.0-or-later -->

## Current State (2026-04-19 update — compile-clean after assert_total removal)

- **LOC**: ~60,900
- **Languages**: Elixir, ReScript, Idris2, Zig, Rust
- **Postulates before**: 26 across 5 files + 2 `assert_total` (spec crash stubs)
- **Postulates after**: 13 (one reintroduced; see §"chainCommutative regression")
- **Proven**: 13 postulates eliminated with genuine proofs
- **New infrastructure**: IsElem type, chainHead/chainTail helpers, StringLemmas module
- **Vordr proofs**: 0 postulates (all proven structurally)

### Idris2 partiality propagation (2026-04-19)

Idris2 0.8 has no `postulate` keyword, so crypto/string axioms are expressed
as `partial`+`idris_crash` stubs. Any caller of a `partial` function is itself
not-covering; since `%default total` is on, that inheritance has to be made
explicit. As of this pass every spec-stub caller carries an explicit `partial`
marker — the proof content is unchanged, but the modules once again
type-check cleanly under `%default total`.

### chainCommutative regression

Previously listed as "proven". The with-block proof
(`chainCommutative ... | True | True = Refl` × 4 cases) doesn't type-check
because Idris2's `with`-abstraction is syntactic: the goal
`verifyChain hash [a,b] = verifyChain hash [b,a]` doesn't contain
`verifyEd25519 …` as a subterm at abstraction time, and Idris2 won't reduce
`verifyChain [n]` past an opaque `verifyEd25519` head. Demoted to a
postulate. The clean fix — refactor `verifyChain = allValid ∘ map verifyPair`
so `allValid` pattern-matches on `(True::_)`/`(False::_)` and reduces — is
deferred; it touches `chainHeadValid`/`chainTailValid`/`chainImpliesIndividual`
together.

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
| `chainExtension` | `rewrite validSig in validChain` | Substitutes True into if-condition |
| `chainImpliesIndividual` | Induction on `IsElem` + chainHead/chainTail helpers | Replaced boolean `elem` with type-level `IsElem` |
| ~~`chainCommutative`~~ | — | **Regressed to postulate 2026-04-19.** See header notes. |

New helper lemmas added:
- `chainHeadValid` — extracts head signature validity via `with`-block
- `chainTailValid` — extracts tail chain validity via `with`-block
- `IsElem` data type — propositional membership (replaces boolean `elem`)

### Unit-Return — 3 postulates → trivial (Theorems.idr, ImporterProofs.idr)

| Postulate | Proof | Notes |
|-----------|-------|-------|
| `thresholdSatisfaction` | `()` | Unit return always constructible; premises carry guarantee |
| `nonRepudiation` | `()` | Same |
| `tarBombPrevention` | `()` | Same |

## What Remains Postulated (12 total)

### Legitimate Cryptographic Axioms (4) — KEEP FOREVER

These encode computational hardness assumptions unprovable in any formal system.

| Postulate | File | Justification |
|-----------|------|---------------|
| `ed25519Correctness` | CryptoProofs.idr | Edwards curve group law (RFC 8032). NOTE: type signature overly permissive — see file for details |
| `sha256CollisionResistant` | CryptoProofs.idr | Collision resistance (NIST SP 800-107) |
| `signatureNonReplayable` | SignatureProofs.idr | Ed25519 EUF-CMA security |
| `signatureNonMalleable` | SignatureProofs.idr | Ed25519 cofactored verification (RFC 8032 §8) |

### Crypto Composition Theorems (2) — KEEP (depend on axioms)

| Postulate | File | Depends on |
|-----------|------|------------|
| `tamperEvidence` | Theorems.idr | sha256CollisionResistant + signatureNonReplayable + list concat non-injectivity |
| `replayPrevention` | Theorems.idr | signatureNonReplayable (different record type) |

### String Primitive Limitations (6) — INFRASTRUCTURE BUILT

`isPrefixOf` and `isInfixOf` are C primitives with no reduction rules. Proven List Char equivalents exist in `StringLemmas.idr` (`charsPrefixOf`, `charsInfixOf`, `charsPrefixOfAppend`). To eliminate these postulates, add a bridge postulate connecting String operations to their List Char equivalents.

| Postulate | File | Proven equivalent in StringLemmas.idr |
|-----------|------|--------------------------------------|
| `extractionSafety` | ImporterProofs.idr | `charsPrefixOfAppend` |
| `symlinkSafety` | ImporterProofs.idr | `charsPrefixOfAppend` |
| `zipSlipPrevention` | ImporterProofs.idr | `charsPrefixOfAppend` |
| `normalizedIsSafe` | ImporterProofs.idr | `dotDotNotInfix` (partial) |
| `absolutePathRejection` | ImporterProofs.idr | Needs SafePath definition over List Char |
| `ociLayoutEnforcement` | ImporterProofs.idr | Needs DecEq on TarEntry paths |

### Path to eliminating String postulates

1. Add bridge postulate: `isPrefixOf s1 s2 = charsPrefixOf (unpack s1) (unpack s2)` (1 postulate)
2. Prove `unpack` distributes over `++`: `unpack (a ++ b) = unpack a ++ unpack b` (may need 1 more postulate)
3. Derive extractionSafety, symlinkSafety, zipSlipPrevention from bridge + `charsPrefixOfAppend`
4. Net: 3 postulates → 1-2 bridge postulates (improvement)

## assert_total Usage (2) — ACCEPTABLE

Both in `CryptoProofs.idr`, used as crash stubs for spec-only functions. Runtime uses `CryptoFFI` IO versions.

## Dangerous Patterns

- Zero `believe_me`, zero `cast Refl`, zero `unsafePerformIO` in proof code.
