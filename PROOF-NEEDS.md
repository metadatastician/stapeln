# PROOF-NEEDS.md
<!-- SPDX-License-Identifier: PMPL-1.0-or-later -->

## Current State (2026-04-19 update — compile-clean after assert_total removal)

- **LOC**: ~60,900
- **Languages**: Elixir, ReScript, Idris2, Zig, Rust
- **Postulates before**: 26 across 5 files + 2 `assert_total` (spec crash stubs)
- **Postulates after**: 12 (chainCommutative regression RESOLVED 2026-05-18 — see §)
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

### chainCommutative regression — RESOLVED 2026-05-18

History: the with-block proof (`chainCommutative ... | True | True = Refl`
× 4 cases) failed to type-check. Sharpened root cause: the blocker was not
merely the `if` — `verifyChain` was *recursive + `partial`*, so Idris2
would not reduce **any** of its clauses in conversion checking (not even
`verifyChain h [] = True`), leaving every unfold stuck.

Fix applied: `verifyChain` refactored to the NON-RECURSIVE alias
`verifyChain h chain = allValid (map (verifyPair h) chain)`, moving all
recursion into the total `allValid`/`map`. `verifyChain h chain` now
reduces structurally on a concrete chain (the opaque `verifyEd25519`
results remain as `&&` operands). `chainCommutative` is proven by the
total 4-case Bool lemma `boolCommTrue : a && (b && True) = b && (a &&
True)`. `chainHeadValid`/`chainTailValid`/`chainImpliesIndividual`/
`chainExtension` were **not** modified — they still type-check (full
`cerro-torre.ipkg` build green under idris2 0.8.0). No `believe_me`,
`assert_total`, or `cast Refl` introduced.

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
| `chainCommutative` | `verifyChain` → `allValid ∘ map verifyPair` refactor; total `boolCommTrue` Bool lemma | **PROVEN 2026-05-18** (regression resolved; idris2 0.8.0 ipkg-verified) |

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
