# stapeln Status (Source of Truth)

**Date:** 2026-03-23

## Product Goal

A reasonably IT-capable 12-year-old can help their parents build a secure container stack without prior container knowledge.

## What Works Today

- **UI Prototype (frontend):** 9 views (51 ReScript modules) in `frontend/src/`, all compiling with 0 errors/warnings.
- **TEA Architecture:** State, Msg, Update, View pattern in App.res. AppIntegrated.res exists as legacy alternative.
- **Pipeline Designer (new):** Full 3-panel node-graph editor (PipelineDesigner, PipelineCanvas, PipelinePalette, PipelineOutput) with SVG canvas, bezier connections, minimap, context menus, drag-drop, 6 pre-built templates, code generation preview.
- **URL-based routing:** AppRouter.res syncs tabs with browser URLs; back/forward navigation works.
- **Undo/redo system:** Snapshot-based with 50-depth cap, Ctrl+Z/Ctrl+Y, visible buttons with disabled state.
- **Auto-save:** 30-second interval with dirty tracking and visual "Saved"/"Unsaved" indicator.
- **Dark mode:** System detection (prefers-color-scheme), localStorage persistence, HTML class sync for Tailwind.
- **Conversational errors:** UX Manifesto Rule 4 pattern (title + reason + [Fix It] buttons) on all API error paths.
- **Import/Export:** Working file picker → TEA dispatch cycle. Import errors show conversational fix suggestions.
- **Security UX Components:** Port config (1,165 lines), security inspector (832 lines), gap analysis (951 lines), simulation mode (1,622 lines) — all fully implemented views, not stubs.
- **Backend API (MVP):** Phoenix REST endpoints for stacks and validation are defined.
- **GraphQL API (MVP):** Absinthe schema at `/api/graphql` is defined.
- **Shared API Boundary:** REST/GraphQL route through `backend/lib/stapeln/native_bridge.ex`.
- **ABI/FFI Contract:** Idris2 ABI (`src/abi/*`) has 8 genuine proofs (no believe_me). Zig FFI (`ffi/zig/src/main.zig`) provides CRUD + validate + dispatch. Real SHA-256 + Ed25519 in `crypto.zig`.
- **VeriSimDB Integration:** Remote client with JSONL local fallback, configurable timeouts.
- **Runtime Boundary:** `stapeln/backend` is the design/control plane. Container lifecycle orchestration is delegated to `container-stack/svalinn` and `container-stack/vordr`.

## What Is Partial or Scaffolded

- **WebSocket integration:** Socket.res exists but no live channel push/receive logic.
- **Auth:** JWT + Plug module present but no token refresh, revocation, or session management. No login UI.
- **Firewall:** Schema present but no nftables integration.
- **Post-Quantum Crypto:** Module scaffolded; no real XMSS implementation.
- **Simulation:** Packet flow UI fully renders with animation and stats but no real backend simulation engine.
- **AttackSurfaceAnalyzer:** Documented in ROADMAP but not yet built (0%).

## Preserved Future Work

- **DOM‑mounter track:** Extracted to `/var$REPOS_DIR/stapeln-dom-mounter`.
- This work is not on the critical path for the container‑hater MVP.

## Architectural Decision: VeriSimDB (2026-03-23)

**All Stapeln data will use VeriSimDB, not PostgreSQL.** Dogfooding decision.
- Dedicated instance: port 8093, volume `stapeln-verisimdb-data`
- Existing `Stapeln.VeriSimDB.Client` module to be extended for stack CRUD
- Ecto/DbStore/PostgreSQL layer to be removed (was a conventional shortcut)
- The PostgreSQL container has been stopped; migrations were verified working but are superseded

## What Is Not Implemented Yet

- **VeriSimDB as primary store:** Client exists for audit logging; needs extending for stack/user/settings CRUD
- **Backend runtime orchestration API:** Not implemented in `stapeln/backend` by design; runtime operations belong to Svalinn/Vordr.
- **Validation Engine Depth:** 12 check categories returning real findings; not yet parity with full security roadmap.
- **Formal Verification Layers:** Idris2 types are now present for ABI contracts, but full proof pipeline is not wired.

## Known Inconsistencies

- Some docs claim a “complete” product; these refer to an internal DOM‑mounter workstream.
- `IMPLEMENTATION-PLAN.md` originated as a legacy `stackur` plan and is now archival context.
- `ROADMAP.adoc` is an alias/deprecation pointer and not the planning source of truth.

## Immediate Focus (Next 4 Weeks)

- Truth-align docs and roadmap.
- Expand backend from MVP to production readiness (durable persistence, broader validation, gRPC/GRC if needed).
- End-user onboarding flow focused on “container haters.”
- Execute the six-stream plan in `docs/EXECUTION-PLAN-2026-02-11.md`.

## Readiness Gate Status

- Current readiness blocker: repo clean gate fails when local edits are present (currently `container-stack/rokur/README.md`).
