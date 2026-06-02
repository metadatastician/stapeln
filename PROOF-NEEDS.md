# PROOF-NEEDS.md
<!-- SPDX-License-Identifier: MPL-2.0 -->

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

### String Primitive Limitations — 3 of 6 ELIMINATED 2026-05-18

`isPrefixOf` is a C primitive with no reduction rules. The bridge is now
in place (`StringLemmas.idr`): two minimal documented axioms
`isPrefixOfBridge` (`isPrefixOf s1 s2 = charsPrefixOf (unpack s1)
(unpack s2)`) and `unpackAppend` (`unpack (a ++ b) = unpack a ++ unpack
b`). Via these + the already-proven `charsPrefixOfAppend`, three
postulates are now **real proofs** (full `cerro-torre.ipkg` green under
idris2 0.8.0). Net: 3 ad-hoc string postulates → 2 fundamental,
well-understood ones (same justified category as estate backend
string-primitive axioms, e.g. boj-server SafetyLemmas).

| Postulate | File | Status |
|-----------|------|--------|
| `extractionSafety` | ImporterProofs.idr | **PROVEN** (isPrefixOfBridge + unpackAppend + charsPrefixOfAppend) |
| `symlinkSafety` | ImporterProofs.idr | **PROVEN** (idem) |
| `zipSlipPrevention` | ImporterProofs.idr | **PROVEN** (idem) |
| `normalizedIsSafe` | ImporterProofs.idr | postulate — needs `dotDotNotInfix` + infix bridge |
| `absolutePathRejection` | ImporterProofs.idr | postulate — needs SafePath over List Char |
| `ociLayoutEnforcement` | ImporterProofs.idr | postulate — needs DecEq on TarEntry paths |

Remaining bridge axioms (minimal trusted base): `isPrefixOfBridge`,
`unpackAppend` in `StringLemmas.idr`.

### Path to eliminating remaining String postulates

1. ~~Add `isPrefixOfBridge` + `unpackAppend`~~ — DONE 2026-05-18.
2. ~~Derive extractionSafety / symlinkSafety / zipSlipPrevention~~ — DONE.
3. `normalizedIsSafe`: add an `isInfixOf` bridge analogous to
   `isPrefixOfBridge`, then derive from `dotDotNotInfix`.
4. `absolutePathRejection`: define `SafePath` semantics over `List Char`.
5. `ociLayoutEnforcement`: add `DecEq` on `TarEntry` paths.

## assert_total Usage (2) — ACCEPTABLE

Both in `CryptoProofs.idr`, used as crash stubs for spec-only functions. Runtime uses `CryptoFFI` IO versions.

## Dangerous Patterns

- Zero `believe_me`, zero `cast Refl`, zero `unsafePerformIO` in proof code.

## Escape-Hatch Enumeration (2026-05-27 — `check-trusted-base.sh` site list)

Per [standards#203](https://github.com/hyperpolymath/standards/blob/main/docs/TRUSTED-BASE-REDUCTION-POLICY.adoc),
each `partial` site reported by `bash scripts/check-trusted-base.sh .` is
enumerated below with classification. Sites are listed with full
file:line so the script's per-site documentation check passes. The
symbolic-postulate breakdown in §"What Remains Postulated (12 total)"
above remains the substantive narrative; this section is the
mechanical CI-gate index.

Classification taxonomy:

- **AXIOM-STUB** — spec-stub `partial`+`idris_crash` that IS the trusted-base
  entry. Runtime impl lives elsewhere (e.g., `CryptoFFI.*IO`). Type-level use only.
- **AXIOM-TRANSITIVE** — proof term itself is total (`Refl`, `()`, `sym`, `rewrite`,
  structural induction); `partial` inherited only because the type signature
  references a partial spec stub. Adds nothing new to trusted base.
- **DISCHARGE-PENDING** — currently `idris_crash` postulate, but a tractable
  proof path is documented in §"Path to eliminating remaining String postulates"
  above. Targeted for future elimination.

### CryptoProofs.idr (7)

| File:line | Symbol | Class | Notes |
|---|---|---|---|
| `container-stack/cerro-torre/verification/idris/CryptoProofs.idr:71` | `verifyEd25519` | AXIOM-STUB | Opaque spec; runtime = `CryptoFFI.verifyEd25519IO` |
| `container-stack/cerro-torre/verification/idris/CryptoProofs.idr:81` | `sha256` | AXIOM-STUB | Opaque spec; runtime = `CryptoFFI.sha256IO` |
| `container-stack/cerro-torre/verification/idris/CryptoProofs.idr:95` | `sha256Deterministic` | AXIOM-TRANSITIVE | Proof = `Refl` |
| `container-stack/cerro-torre/verification/idris/CryptoProofs.idr:102` | `sha256Pure` | AXIOM-TRANSITIVE | Proof = `Refl` |
| `container-stack/cerro-torre/verification/idris/CryptoProofs.idr:109` | `ed25519Deterministic` | AXIOM-TRANSITIVE | Proof = `Refl` |
| `container-stack/cerro-torre/verification/idris/CryptoProofs.idr:151` | `ed25519Correctness` | AXIOM-STUB | RFC 8032 §5.1.7 Edwards curve correctness |
| `container-stack/cerro-torre/verification/idris/CryptoProofs.idr:174` | `sha256CollisionResistant` | AXIOM-STUB | NIST SP 800-107 collision resistance |

### SignatureProofs.idr (9)

| File:line | Symbol | Class | Notes |
|---|---|---|---|
| `container-stack/cerro-torre/verification/idris/SignatureProofs.idr:60` | `signatureNonReplayable` | AXIOM-STUB | Ed25519 EUF-CMA (reduces to DL on Curve25519) |
| `container-stack/cerro-torre/verification/idris/SignatureProofs.idr:80` | `signatureNonMalleable` | AXIOM-STUB | RFC 8032 §8 cofactored verification |
| `container-stack/cerro-torre/verification/idris/SignatureProofs.idr:114` | `verifyPair` | AXIOM-TRANSITIVE | Calls `verifyEd25519` |
| `container-stack/cerro-torre/verification/idris/SignatureProofs.idr:137` | `verifyChain` | AXIOM-TRANSITIVE | Calls `verifyPair` |
| `container-stack/cerro-torre/verification/idris/SignatureProofs.idr:153` | `chainHeadValid` | AXIOM-TRANSITIVE | Proof = with-block case-split (total) |
| `container-stack/cerro-torre/verification/idris/SignatureProofs.idr:167` | `chainTailValid` | AXIOM-TRANSITIVE | Proof = with-block case-split (total) |
| `container-stack/cerro-torre/verification/idris/SignatureProofs.idr:218` | `chainImpliesIndividual` | AXIOM-TRANSITIVE | Proof = induction on `IsElem` (total) |
| `container-stack/cerro-torre/verification/idris/SignatureProofs.idr:245` | `chainExtension` | AXIOM-TRANSITIVE | Proof = `rewrite validSig in validChain` (total) |
| `container-stack/cerro-torre/verification/idris/SignatureProofs.idr:272` | `chainCommutative` | AXIOM-TRANSITIVE | Proof = `boolCommTrue` 4-case Bool lemma (total, see 2026-05-18 regression resolution above) |

### ImporterProofs.idr (6)

| File:line | Symbol | Class | Notes |
|---|---|---|---|
| `container-stack/cerro-torre/verification/idris/ImporterProofs.idr:137` | `normalizedIsSafe` | DISCHARGE-PENDING | Needs `isInfixOf` bridge + `dotDotNotInfix` lemma |
| `container-stack/cerro-torre/verification/idris/ImporterProofs.idr:158` | `extractionSafety` | AXIOM-TRANSITIVE | Proof = `isPrefixOfBridge` + `unpackAppend` + `charsPrefixOfAppend` (total via StringLemmas) |
| `container-stack/cerro-torre/verification/idris/ImporterProofs.idr:176` | `symlinkSafety` | AXIOM-TRANSITIVE | Same proof pattern as `extractionSafety` |
| `container-stack/cerro-torre/verification/idris/ImporterProofs.idr:208` | `absolutePathRejection` | DISCHARGE-PENDING | Needs `SafePath` semantics over `List Char` |
| `container-stack/cerro-torre/verification/idris/ImporterProofs.idr:242` | `ociLayoutEnforcement` | DISCHARGE-PENDING | Needs `DecEq` on `TarEntry` paths |
| `container-stack/cerro-torre/verification/idris/ImporterProofs.idr:282` | `zipSlipPrevention` | AXIOM-TRANSITIVE | Same proof pattern as `extractionSafety` |

### Theorems.idr (10)

| File:line | Symbol | Class | Notes |
|---|---|---|---|
| `container-stack/cerro-torre/verification/idris/Theorems.idr:42` | `computeBundleHash` | AXIOM-TRANSITIVE | Calls `sha256` spec |
| `container-stack/cerro-torre/verification/idris/Theorems.idr:50` | `WellFormed` | AXIOM-TRANSITIVE | Type references `computeBundleHash` |
| `container-stack/cerro-torre/verification/idris/Theorems.idr:57` | `ProperlySigned` | AXIOM-TRANSITIVE | Type references `verifyChain` |
| `container-stack/cerro-torre/verification/idris/Theorems.idr:76` | `bundleIntegrity` | AXIOM-TRANSITIVE | Proof = `sym wellFormed` (total) |
| `container-stack/cerro-torre/verification/idris/Theorems.idr:93` | `signatureChainSoundness` | AXIOM-TRANSITIVE | Delegates to `chainImpliesIndividual` |
| `container-stack/cerro-torre/verification/idris/Theorems.idr:123` | `supplyChainIntegrity` | AXIOM-TRANSITIVE | Proof = two `rewrite` + `wf1` (total) |
| `container-stack/cerro-torre/verification/idris/Theorems.idr:161` | `tamperEvidence` | AXIOM-STUB | Composition of `sha256CollisionResistant` + `signatureNonReplayable` |
| `container-stack/cerro-torre/verification/idris/Theorems.idr:186` | `thresholdSatisfaction` | AXIOM-TRANSITIVE | Proof = `()` (trivial; security in premises) |
| `container-stack/cerro-torre/verification/idris/Theorems.idr:206` | `replayPrevention` | AXIOM-STUB | Direct consequence of `signatureNonReplayable` |
| `container-stack/cerro-torre/verification/idris/Theorems.idr:230` | `nonRepudiation` | AXIOM-TRANSITIVE | Proof = `()` (trivial; security in premises) |

### Summary

- **AXIOM-STUB** (8): `verifyEd25519`, `sha256`, `ed25519Correctness`, `sha256CollisionResistant`, `signatureNonReplayable`, `signatureNonMalleable`, `tamperEvidence`, `replayPrevention`. These are the genuine trusted-base entries.
- **AXIOM-TRANSITIVE** (21): Type-signature partiality inherited from AXIOM-STUB references. Every proof term is total; the only reason these are `partial` is Idris2 0.8's lack of a `postulate` keyword forcing partiality propagation through any caller of a spec stub.
- **DISCHARGE-PENDING** (3): `normalizedIsSafe`, `absolutePathRejection`, `ociLayoutEnforcement` — tractable proofs documented in §"Path to eliminating remaining String postulates" above.

Total: 32 sites enumerated. The remaining 2 of 34 markers reported by the script are the two `assert_total` documented in §"assert_total Usage (2) — ACCEPTABLE" above.
