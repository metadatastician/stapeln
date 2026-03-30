# PROOF-NEEDS.md
<!-- SPDX-License-Identifier: PMPL-1.0-or-later -->

## Current State

- **LOC**: ~60,900
- **Languages**: Elixir, ReScript, Idris2, Zig, Rust
- **Existing ABI proofs**: Extensive — `src/abi/Proofs.idr`, `src/abi/Layout.idr`, cerro-torre verification suite (CryptoProofs, ImporterProofs, SignatureProofs, Theorems), vordr Idris2 proofs
- **Dangerous patterns**:
  - `src/abi/Layout.idr`: 4 `postulate` (memory layout alignment — Idris2 cannot reduce `sumFieldSizes`)
  - `src/abi/Proofs.idr`: 5 `postulate` (service spec contiguity — concrete numeric equalities)
  - `cerro-torre/verification/idris/CryptoProofs.idr`: 5 `postulate` (crypto axioms) + 2 `assert_total` (crash stubs)
  - `cerro-torre/verification/idris/ImporterProofs.idr`: 9 `postulate`
  - `cerro-torre/verification/idris/SignatureProofs.idr`: 7 `postulate`
  - `cerro-torre/verification/idris/Theorems.idr`: 11 `postulate`
  - `container-stack/svalinn/` and `vordr/`: `Obj.magic` in ReScript clients

## What Needs Proving

### Layout Postulates (src/abi/Layout.idr)
- 4 postulates about memory alignment and field size summation
- These are concrete arithmetic facts that SHOULD be provable with enough normalization effort
- Try: Idris2 `%hint` or manual Nat arithmetic proofs

### Service Spec Contiguity (src/abi/Proofs.idr)
- 5 postulates asserting `fieldEnd field_n = offset field_{n+1}`
- These are concrete numeric equalities (e.g., `fieldEnd (MkFieldLayout "name_ptr" 0 8) = offset (MkFieldLayout "name_len" 8 8)`)
- Should be mechanically provable by evaluation — likely need `%runElab` or explicit `Refl`

### Cerro-Torre Crypto Axioms
- `ed25519Correctness`, `sha256CollisionResistant` — these are cryptographic assumptions, legitimately postulated
- `assert_total` crash stubs — acceptable as runtime guards but should be documented as FFI boundaries
- ImporterProofs (9) and SignatureProofs (7) postulates need audit — some may be provable

### Cerro-Torre Theorems (11 postulates)
- Highest count of unproven claims — need individual assessment of which are axioms vs. provable lemmas

### Vordr Container Verification
- `vordr/src/idris2/Proofs.idr` — verify attestation chain integrity
- Container launch preconditions should have machine-checked proofs

## Recommended Prover

- **Idris2** (already in use — deepen existing proofs, eliminate arithmetic postulates)
- Consider **Lean4** for the harder theorems if Idris2 normalization is insufficient

## Priority

**HIGH** — Container orchestration system with security-critical crypto verification. 41+ postulates across the proof suite, many of which appear mechanically provable. The crypto axioms are acceptable but the arithmetic and contiguity postulates should be eliminated.

## Template ABI Cleanup (2026-03-29)

Template ABI removed -- was creating false impression of formal verification.
The removed files (Types.idr, Layout.idr, Foreign.idr) contained only RSR template
scaffolding with unresolved {{PROJECT}}/{{AUTHOR}} placeholders and no domain-specific proofs.
