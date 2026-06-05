<!-- SPDX-License-Identifier: MPL-2.0 -->
# PROOF-BACKLOG — working-through-the-proofs tracker

Status as of the first compact boundary. This is the **spine** (original thread
intent: "work through the proofs"). Side-projects are listed at the bottom for
disposal to separate Claude sessions (GitHub issues).

## Toolchain (already installed in this session's container)
- **idris2 0.8.0** at `/root/.idris2/bin` (Chez backend). `export PATH=/root/.idris2/bin:$PATH`.
- **Alire 2.0.2 + GNAT 14.2.1 + gnatprove 14.1.1** (for SPARK), via `alr` (`/usr/local/bin/alr`).
- AffineScript toolchain NOT built (blocked — needs user authorization to `opam install` the external repo).
- `idris2 --check FILE` returns **exit 0 even on errors** — always grep output for `Error:`.

## ✅ VERIFIED CLEAN (compile green)
| Package | How |
|---|---|
| cerro-torre `cerro-torre.ipkg` (7 mods) | `idris2 --build` green; CI green |
| vordr `vordr.ipkg` (6 mods) | repaired this session → green |
| `stapeln-tests.ipkg` (8 mods) | green |
| `container-stack/selur/idris/{Proofs,Theorems}.idr` | `--check` clean |
| `dom-mounter/{src/abi/DomMounter,docs/DomMounterSecurity,docs/DomMounterEnhanced}.idr` | clean |
| `frontend/src/abi/FileIO.idr` | clean |
| SPARK `gnatprove -P cerro_torre.gpr --level=2` | exits 0 (CI green) |

## 🔴 REMAINING PROOF WORK (drive to "clear" — user bar: DISCHARGE EVERYTHING)

### 1. ABI layer repair — ✅ DONE (`src/abi/abi.ipkg` builds, exit 0, honest)
Root cause: estate `<Project>.ABI.<Module>` modules lived in **flat** `src/abi/X.idr`
files — idris2 rejects this (module name ≠ path), so the layer never compiled.
**DECISION TAKEN: rename modules to flat** (`Types`/`Layout`/`Proofs`/`Foreign`),
matching the rest of the estate (dom-mounter, selur are flat-per-package). Nothing
imports these (self-contained); only docs reference the old `Stapeln.ABI.*` paths
(stale doc drift, low priority — see §6). If the namespace must be preserved later,
relocate the files into `Stapeln/ABI/` + set `sourcedir` accordingly.

Defects found & fixed to get a genuine green build (all honest — no believe_me):
- **`Result` ABI drift (correctness).** `ResultCode` had `NotFound=3, OutOfMemory=4`
  and no `NullPointer`, but the authoritative C ABI (`ffi/zig/src/main.zig`:
  `out_of_memory=3, null_pointer=4`) and `Foreign.idr`'s own `resultFromInt` use
  `OutOfMemory=3, NullPointer=4`. The round-trip/injectivity proofs were therefore
  honest-but-vacuous w.r.t. the real FFI boundary. Realigned `ResultCode` to the
  Zig source of truth (+ `Result` alias); proofs now describe the actual boundary.
- **`NonEmpty` erased-witness (soundness of the API).** `IsNonEmpty` carried a
  vacuous `{auto prf : s = s}` and an **erased** (`0 _`) non-emptiness witness, so
  `Not (NonEmpty "")` was impossible to discharge. Made the witness relevant.
- **Two typecheck hangs** (each pinned chez at 100% CPU, never terminated):
  (a) `resultToIntInjective` used `absurd prf` over `Int` equality — the
  `Uninhabited (resultToInt a = resultToInt b)` search does not reduce the imported
  `resultToInt` and diverges; replaced with `Refl impossible` clauses (coverage
  checker refutes distinct `Int` literals directly). (b) `portNNValid` left the
  `LTE n 65535` bound to `{auto}` search, which blows up with Data.Nat's LTE hints;
  supply it explicitly via `lteAddRight`.
- `Layout.idr`: missing `import Data.List.Quantifiers` (so `All` resolved to Prelude
  Bool `All`); `fields serviceSpecLayout` in type sigs auto-bound `serviceSpecLayout`
  as a fresh implicit → use qualified `Layout.serviceSpecLayout`; hoisted total
  `lastField` out of an invalid `where` (had a `?impossible_empty_layout` hole).
- `Types.idr`: hoisted `NonEmptyProof` out of an invalid `where` (constructor renamed
  `IsNonEmpty`→`IsNonEmptyList`).
- `Proofs.idr`: missing `import Data.List.Elem`; `resultCodeComplete` referred to the
  CAF `allResultCodes` which won't unfold under `Elem`'s `Here/There` — inlined the
  literal list; `validStackNonEmpty` pattern omitted the explicit `allNamed` arg.
- `Foreign.idr`: `Handle`/`createHandle` were undefined — added (Bits64 wrapper +
  null-reject); `registerCallback` did `cast cb` (closure→AnyPtr, no Cast, would
  need believe_me) — declared the `%foreign` prim with the `Callback` function type
  so Idris marshals the closure honestly.
- `abi.ipkg`: `sourcedir=".", depends=base,contrib, modules=Types,Layout,Proofs,Foreign`.
- Build: `cd src/abi && idris2 --build abi.ipkg` (~26s; Types alone ~23s — see note).

NOTE (perf, non-blocking): `Types.idr` typechecks in ~23s and emits a 39 MB `.ttc`,
abnormal for a small module. Not yet root-caused; CI budget (30 min) absorbs it.
Candidate follow-up. `src/abi/abi.ipkg` is NOT yet wired into a CI gate (the
`formal-verification.yml` gate is cerro-torre-scoped) — consider adding it so this
layer is regression-protected.

### 2. `container-stack/vordr/src/abi/` — ✅ DONE (orphan repaired, builds)
Reality differed from the earlier note: only `Foreign.idr` existed (module
`Vordr.ABI.Foreign`), importing non-existent `Vordr.ABI.Types`/`Vordr.ABI.Layout`,
and NOTHING built it (the only Idris2 package manifest, `vordr.ipkg`, lives in
vordr's Idris2 source tree and does not include this abi directory). Created
`Types.idr` (flat module; `Result` matching vordr's Zig ABI in its `ffi/zig` FFI
layer + `resultToInt`/`DecEq` + injectivity & round-trip proofs,
same honest patterns proven in stapeln's src/abi), renamed `Foreign`→flat, added
`Handle`/`createHandle`, dropped the unused `Layout` import, replaced the unsound
`cast cb` with a `Callback`-typed `%foreign`, and added `abi.ipkg`
(`modules=Types,Foreign`). Builds exit 0 (~0.8s), no believe_me. (Layout was
unused, so not recreated.) Same "wire into a CI gate" note as §1 applies.

### 3. cerro-torre `normalizedIsSafe` — ✅ DISCHARGED (2026-06)
`ImporterProofs.idr`. Was **false as stated**: SafePath admitted only trailing-slash
paths {"","a/","a/b/"}, disjoint from normalizePath's no-trailing-slash output
{"","a","a/b"} — so `SafePath (normalizePath p)` was uninhabited for any non-empty
path. Redesigned SafePath (SafeSingle leaf + '/'-free via `charsElem` + non-empty
rest), re-proved `absolutePathRejection`, then discharged
`normalizedIsSafe = joinBySafe ∘ mkAllSafe` (verified split/filter/joinSep recursion).
Trusted base grew by exactly **2** fundamental opaque-String-primitive axioms:
`splitNoDelim` (split components are '/'-free) + `dotDotInfixOfJoin` (a ".." component
is a ".." infix of the join). ~13 supporting lemmas all total; no believe_me/cast
Refl/assert_total. `cerro-torre.ipkg` builds 7/7 green. (PR #94.)

### 4. SPARK `cerro_ctp_lexer` unproved VCs
`medium`/`low` (loop invariants, range checks). gnatprove exits 0 today (non-fatal),
but "discharge everything" ⇒ add loop invariants to clear them. Iterate locally:
`cd container-stack/cerro-torre && alr -n build || true && alr -n exec -- gnatprove -P cerro_torre.gpr --level=2 --report=fail --output-msg-only`.

### 5. ATS `.dats` (6 files) — never verified (no ATS2 toolchain)
`cerro-torre/verification/ats/*.dats` + `tools/ats-shadow/*.dats`. Needs `postiats`
(patsopt). **May hit the same external-build authorization wall as affinescript.**

### 6. Final: PROOF-NEEDS + trusted-base audit estate-wide; confirm zero
believe_me/cast Refl/assert_total everywhere.

## Trusted base (KEEP — genuine)
cerro-torre: 8 crypto AXIOM-STUBs (hardness/composition) + 4 string-primitive
bridges (`isPrefixOfBridge`, `unpackAppend`, `eqStringSym`, `unpackEmptyInv`) +
**2 path-normalization axioms** (`splitNoDelim`, `dotDotInfixOfJoin`, from the
normalizedIsSafe discharge) + 4 CryptoFFI runtime stubs. Zero believe_me/cast
Refl/assert_total in cerro-torre or vordr proof code.

## 🟢 FALSE theorems found & fixed this session (do not regress)
- `absolutePathRejection` (SafePath admitted absolute paths — path-traversal gap) → fixed.
- vordr `StartIsReversible` (no Running→Created transition; ill-typed inverse) → removed.
- vordr `nonAdminCantPrivilege` (unsound + undefined types) → disabled w/ rationale.

## 📦 SIDE-PROJECTS — ✅ HANDED OFF (filed as GitHub issues 2026-06-05)
1. **AffineScript migration** → **stapeln#92**. `.ts`(9, banned)+`.res`(164)→AffineScript.
   Pilot: `svalinn_gateway.ts`→jaffascript. Needs: authorize building
   `hyperpolymath/affinescript` (OCaml/opam). `jaffascript`=brand surface;
   compiler=`affinescript` (`affinescript check --face jaffa FILE`).
2. **CI hardening remainder (Hypatia highs/criticals)** → **stapeln#91**. `instant-sync.yml`
   secret-presence-gate; `scorecard-enforcer.yml` split publish job; `codeql.yml`
   add `actions` language; the banned `.ts` (criticals). Reusable-caller
   `missing_timeout` flags are NOT fixable in-repo (GitHub disallows timeout on `uses:` jobs).
3. **svalinn greenfield proofs** → **svalinn#34**. 177 `Obj.magic` in auth/MCP/policy;
   gated on the AffineScript migration. svalinn PR #32 also red on pre-existing Type/Lint/Format.
4. **Estate CLAUDE.md sweep** → **stapeln#93**. propagate ReScript→AffineScript
   reconciliation to the other repos via the rsr-template-repo (only stapeln+svalinn done here).

The Hypatia advisory scan (444 findings: 20 critical / 149 high / 275 medium) is
`--exit-zero` (non-blocking); its findings == items 1+2 above. The code-scanning
`Hypatia` check tracks PR-INTRODUCED alerts only — keep new files free of dangling
path tokens (a path naming a top-level dir that does not exist at repo root is
substring-matched and flagged as structural_drift) to keep it green.

## Done & shipped (PR hyperpolymath/stapeln#89, all gates green)
cerro-torre discharges (ociLayoutEnforcement, absolutePathRejection + SafePath fix);
vordr repair; SPARK gate fix (config-gen + SPARK_Mode consistency); CI root-fixes
(A2ML carve-out, `.hypatia-baseline.json` for .res/.dats, workflow pin+timeouts);
CLAUDE.md ReScript→AffineScript reconciliation (stapeln #89 + svalinn #32).
