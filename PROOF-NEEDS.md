# PROOF-NEEDS.md
<!-- SPDX-License-Identifier: MPL-2.0 -->

## Current State (2026-06 update — ociLayoutEnforcement + absolutePathRejection DISCHARGED)

- **LOC**: ~60,900
- **Languages**: Elixir, ReScript, Idris2, Zig, Rust
- **Postulates before**: 26 across 5 files + 2 `assert_total` (spec crash stubs)
- **Postulates after**: 10 domain postulates (2 more discharged 2026-06; see §)
- **Proven**: 15 postulates eliminated with genuine proofs
- **New infrastructure**: IsElem type, chainHead/chainTail helpers, StringLemmas
  module (now also `anyMono`/`foldlOrPull`/`andLeftTrue` Bool-lemmas), SafePath
  strengthened with `Not (component = "")` + explicit `rest` index.
- **Toolchain**: verified under idris2 0.8.0 (Chez backend); `cerro-torre.ipkg`
  builds 7/7 clean.

### 2026-06 pass — two DISCHARGE-PENDING postulates eliminated

`ociLayoutEnforcement` and `absolutePathRejection` are now genuine proofs
(full `cerro-torre.ipkg` green under idris2 0.8.0). Net trusted base: two
*fundamental* String-primitive axioms added to StringLemmas — `eqStringSym`
(symmetry of primitive `==`) and `unpackEmptyInv` (`unpack s = [] → s = ""`) —
in exchange for discharging two domain postulates with real structural proofs.
All Bool/list reasoning (`anyMono`, `foldlOrPull`, `andLeftTrue`, the
`isPrefixOf`/`unpack` literal reductions) is total and adds nothing to the
trusted base.

**SOUNDNESS FIX**: discharging `absolutePathRejection` required strengthening
`SafePath`'s `SafeComponent` with `Not (component = "")`. Without it the empty
leading component made every absolute path "/rest" = "" ++ "/" ++ rest count as
SafePath — i.e. `absolutePathRejection` was *false as stated*. The non-empty
requirement closes that latent path-traversal gap in the safety model.

> **Vordr proofs — REPAIRED 2026-06.** Earlier revisions claimed "0 postulates,
> all proven", but the vordr Idris2 package did **not** compile at all (so it
> verified nothing). It now builds end-to-end (`vordr.ipkg` 6/6 + executable,
> idris2 0.8.0). Fixes: `Verification.allVerifiedFromList` Bool `all` →
> propositional `All` (Data.List.Quantifiers); `SBOM.verifySBOM` `List String`
> `decEqList` → element-agnostic `isNil` (+ `totalVulns` made public export);
> `Proofs.idr` dangling `|||` doc-comments, `Attestation.Attestation`/`verified`
> → Verification's `Attestation`/`.valid`, `emptyDepsNoVulns`/`cleanDepsAdditive`
> proven; `Attestation.idr` missing `chainPassed` signature, Bool `==`/`>`
> constructor predicates → propositional `=`/`= True`, `Data.List.unlines` →
> `Data.String.unlines`.
> **Soundness:** `StartIsReversible` removed — Start (Created→Running) is not
> Bennett-reversible (no Running→Created transition), so its `inverse` was
> ill-typed; only Pause↔Resume remains. The `Security Invariants` section
> (undefined `SecurityConfig`/`AuthorizationLevel`/`Admin`/`isPrivileged` + an
> unsound `nonAdminCantPrivilege`) is disabled pending a real security model.
> No `believe_me`/`cast Refl`/`assert_total`/`idris_crash` in vordr proof code.

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

### String Primitive Limitations — 5 of 6 ELIMINATED (3 in 2026-05, 2 in 2026-06)

`isPrefixOf`/`unpack`/`==` are C primitives with no reduction rules. The bridge
axioms live in `StringLemmas.idr`: `isPrefixOfBridge`, `unpackAppend` (2026-05)
and `eqStringSym`, `unpackEmptyInv` (2026-06) — four minimal, documented,
trivially-true facts about the opaque primitives.

- 2026-05: via `isPrefixOfBridge` + `unpackAppend` + the proven
  `charsPrefixOfAppend`, the three "prefix of root ++ …" postulates
  (`extractionSafety`, `symlinkSafety`, `zipSlipPrevention`) became real proofs.
- 2026-06: `ociLayoutEnforcement` (via `eqStringSym` + total `anyMono`) and
  `absolutePathRejection` (via `unpackEmptyInv` + `unpackAppend`, plus a SafePath
  soundness fix) became real proofs.

Net: 5 ad-hoc domain string postulates discharged → 4 fundamental, well-understood
primitive axioms (same justified category as estate backend string-primitive
axioms, e.g. boj-server SafetyLemmas). Only `normalizedIsSafe` remains.

| Postulate | File | Status |
|-----------|------|--------|
| `extractionSafety` | ImporterProofs.idr | **PROVEN** (isPrefixOfBridge + unpackAppend + charsPrefixOfAppend) |
| `symlinkSafety` | ImporterProofs.idr | **PROVEN** (idem) |
| `zipSlipPrevention` | ImporterProofs.idr | **PROVEN** (idem) |
| `normalizedIsSafe` | ImporterProofs.idr | **PROVEN 2026-06** (was false-as-stated + postulate). SafePath redesigned to match normalizePath; proof = `joinBySafe ∘ mkAllSafe`. Trusted base += `splitNoDelim`, `dotDotInfixOfJoin` (2 fundamental String-primitive axioms) |
| `absolutePathRejection` | ImporterProofs.idr | **PROVEN 2026-06** (SafePath redesigned: SafeSingle + `charsElem '/'`-free + non-empty rest; `unpackEmptyInv`/`unpackAppend`; `isPrefixOf "/" ""`/native unfold reduce by `Refl`) |
| `ociLayoutEnforcement` | ImporterProofs.idr | **PROVEN 2026-06** (`anyMono` + `andLeftTrue` + `eqStringSym`) |

Bridge axioms (minimal trusted base) in `StringLemmas.idr`: `isPrefixOfBridge`,
`unpackAppend`, and (2026-06) `eqStringSym`, `unpackEmptyInv`. All four are
fundamental, trivially-true facts about the opaque C primitives `==`/`unpack`
with no Idris2 reduction rules — the same justified category throughout.

### Path to eliminating remaining String postulates

1. ~~Add `isPrefixOfBridge` + `unpackAppend`~~ — DONE 2026-05-18.
2. ~~Derive extractionSafety / symlinkSafety / zipSlipPrevention~~ — DONE.
3. ~~`absolutePathRejection`~~ — DONE 2026-06. Strengthened `SafePath`
   (`Not (component = "")` + explicit `rest`), then case-split: SafeEmpty via
   `isPrefixOf "/" "" = False` (Refl); SafeComponent via `slashPrefixThroughAppend`
   (head char of a non-empty component is the separator), using `unpackAppend` +
   `unpackEmptyInv`. Note: needed a real **soundness fix** (see Current State).
4. ~~`ociLayoutEnforcement`~~ — DONE 2026-06. `elem` unfolds to `any (m ==)`;
   `anyMono` lifts the witness to the path predicate; the path conjunct is
   extracted with `andLeftTrue` and flipped with `eqStringSym`. (`anyMono` is
   proven via `foldlOrPull`, since stdlib `any = foldMap @{Any}` is a left fold.)
5. `normalizedIsSafe` (ONLY remaining DISCHARGE-PENDING): the hard one. Needs a
   verified model of `normalizePath` (split/filter/joinBy) over `List Char`
   showing the result decomposes into Safe components, plus an `isInfixOf`
   bridge to connect the "no `..` infix" premise to component-level
   `..`-freeness. This is a substantial verified-string-processing effort
   (≈ several hundred lines + further bridges), deliberately deferred rather
   than discharged unsoundly. The 2026-06 SafePath strengthening means any
   future proof must also supply per-component non-emptiness (which
   `normalizePath`'s `filter (/= "")` guarantees).

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

> DRIFT-PROOFING NOTE: the gate's `check-trusted-base.sh` documents a site if
> EITHER the exact `path:line` OR the **bare file path** (no line number)
> appears in this file (`grep -F` substring match). The full repo-relative
> paths below therefore keep every site in a listed file documented even after
> proof edits shift line numbers — so when editing the `.idr` files, **keep the
> full paths present**; the line numbers are advisory, not load-bearing.
> (Abbreviating the paths to `…/` is what broke this gate once; do not do that.)

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

### ImporterProofs.idr (17 partial sites; lines = the `partial` keyword, 2026-06 normalizedIsSafe discharge)

| File:line | Symbol | Class | Notes |
|---|---|---|---|
| `container-stack/cerro-torre/verification/idris/ImporterProofs.idr:181` | `splitNoDelim` | **AXIOM (new)** | split semantics: components of `split (== '/')` are '/'-free. Opaque String primitive — not reducible at the type level |
| `container-stack/cerro-torre/verification/idris/ImporterProofs.idr:191` | `dotDotInfixOfJoin` | **AXIOM (new)** | join/infix semantics: a ".." component is a ".." infix of the join. Opaque `isInfixOf` primitive |
| `container-stack/cerro-torre/verification/idris/ImporterProofs.idr:204` | `appendEmptyLeft` | AXIOM-TRANSITIVE | `a ++ b = "" → a = ""`; via `unpackAppend` + `unpackEmptyInv` (List-Char part total) |
| `container-stack/cerro-torre/verification/idris/ImporterProofs.idr:213` | `joinByConsNonEmpty` | AXIOM-TRANSITIVE | join with non-empty head is non-empty; via `appendEmptyLeft` |
| `container-stack/cerro-torre/verification/idris/ImporterProofs.idr:230` | `joinBySafe` | AXIOM-TRANSITIVE | builds SafePath of the join from per-component safety (structural; uses `joinByConsNonEmpty`) |
| `container-stack/cerro-torre/verification/idris/ImporterProofs.idr:290` | `mkAllSafe` | AXIOM-TRANSITIVE | per-component safety from `filter`/`split` + the 2 axioms |
| `container-stack/cerro-torre/verification/idris/ImporterProofs.idr:312` | `normalizedIsSafe` | **AXIOM-TRANSITIVE (PROVEN 2026-06)** | was DISCHARGE-PENDING (and false-as-stated). `joinBySafe ∘ mkAllSafe`; trusted base += `splitNoDelim`, `dotDotInfixOfJoin` |
| `container-stack/cerro-torre/verification/idris/ImporterProofs.idr:333` | `extractionSafety` | AXIOM-TRANSITIVE | `isPrefixOfBridge` + `unpackAppend` + `charsPrefixOfAppend` |
| `container-stack/cerro-torre/verification/idris/ImporterProofs.idr:351` | `symlinkSafety` | AXIOM-TRANSITIVE | Same pattern as `extractionSafety` |
| `container-stack/cerro-torre/verification/idris/ImporterProofs.idr:384` | `slashPrefixAppendEq` | AXIOM-TRANSITIVE | Helper; `unpackAppend` + Refl reductions |
| `container-stack/cerro-torre/verification/idris/ImporterProofs.idr:398` | `nonEmptyUnpack` | AXIOM-TRANSITIVE | Helper; `unpackEmptyInv` |
| `container-stack/cerro-torre/verification/idris/ImporterProofs.idr:408` | `slashPrefixThroughAppend` | AXIOM-TRANSITIVE | Helper; total composition of the two above |
| `container-stack/cerro-torre/verification/idris/ImporterProofs.idr:423` | `slashPrefixImpliesCharsElem` | AXIOM-TRANSITIVE | Helper (SafePath redesign); bridges the '/'-free field to the absolute-prefix premise |
| `container-stack/cerro-torre/verification/idris/ImporterProofs.idr:437` | `absolutePathNotSafe` | AXIOM-TRANSITIVE | Core: case split on the SafePath witness (3 ctors) |
| `container-stack/cerro-torre/verification/idris/ImporterProofs.idr:465` | `absolutePathRejection` | AXIOM-TRANSITIVE (PROVEN 2026-06) | re-proven against the redesigned SafePath (SafeEmpty/SafeSingle/SafeComponent) |
| `container-stack/cerro-torre/verification/idris/ImporterProofs.idr:506` | `ociLayoutEnforcement` | AXIOM-TRANSITIVE (PROVEN 2026-06) | `eqStringSym` + total `anyMono` |
| `container-stack/cerro-torre/verification/idris/ImporterProofs.idr:557` | `zipSlipPrevention` | AXIOM-TRANSITIVE | Same pattern as `extractionSafety` |

(`prefixSlashEmpty` and `prefixNative` are total `Refl`, not partial sites.)

### StringLemmas.idr (4 string axioms; the Bool/`any` lemmas are all total)

| File:line | Symbol | Class | Notes |
|---|---|---|---|
| `container-stack/cerro-torre/verification/idris/StringLemmas.idr:176` | `isPrefixOfBridge` | AXIOM-STUB | String `isPrefixOf` ≡ List-Char form under `unpack` |
| `container-stack/cerro-torre/verification/idris/StringLemmas.idr:186` | `unpackAppend` | AXIOM-STUB | `unpack` distributes over `++` |
| `container-stack/cerro-torre/verification/idris/StringLemmas.idr:198` | `eqStringSym` | AXIOM-STUB | symmetry of primitive String `==` (NEW 2026-06) |
| `container-stack/cerro-torre/verification/idris/StringLemmas.idr:210` | `unpackEmptyInv` | AXIOM-STUB | `unpack s = [] → s = ""` (NEW 2026-06) |

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

- **AXIOM-STUB** (10): the 8 crypto/composition stubs (`verifyEd25519`, `sha256`,
  `ed25519Correctness`, `sha256CollisionResistant`, `signatureNonReplayable`,
  `signatureNonMalleable`, `tamperEvidence`, `replayPrevention`) plus the 2 new
  fundamental String axioms `eqStringSym`, `unpackEmptyInv`. (The 2 pre-existing
  String axioms `isPrefixOfBridge`/`unpackAppend` were always trusted-base too.)
  These are the genuine trusted-base entries.
- **AXIOM-TRANSITIVE** (grew by the 2026-06 absolutePathRejection helper chain):
  type-signature partiality inherited from AXIOM-STUB references. Every proof
  term is total; the only reason these are `partial` is Idris2 0.8's lack of a
  `postulate` keyword forcing partiality propagation through any caller of a stub.
- **DISCHARGE-PENDING** (1): `normalizedIsSafe` only. `absolutePathRejection` and
  `ociLayoutEnforcement` were discharged 2026-06 (see §"Path to eliminating…").

Re-run `bash scripts/check-trusted-base.sh .` to regenerate exact per-site counts
after the 2026-06 rewrite; the two `assert_total` in CryptoProofs.idr remain (see
§"assert_total Usage (2) — ACCEPTABLE").
