// SPDX-License-Identifier: CC-BY-SA-4.0

# stapeln Roadmap

**Goal**: Convert container-haters into container-users through game-like UX and built-in security

**Product Test**: A reasonably IT-capable 12-year-old can help their parents build a secure container stack without prior container knowledge.

**Target 1.0 Release**: Q3 2026

---

## Current State (2026-03-29)

**Honest completion: ~87%**

| Component | Status | Notes |
|-----------|--------|-------|
| UI (9 views, 51 modules) | Working | All render, navigate, TEA pattern solid |
| Pipeline Designer | Working | 3-panel node-graph editor, SVG canvas, bezier connections, minimap, 6 templates |
| URL-based routing | Working | AppRouter.res syncs tabs with browser URLs |
| Undo/redo system | Working | Snapshot-based, 50-depth cap, Ctrl+Z/Ctrl+Y |
| Auto-save | Working | 30-second interval with dirty tracking |
| Dark mode | Working | System detection + localStorage persistence |
| Import/Export | Working | File picker, JSON + compose files, real container images |
| Security UX (4 views) | Working | Port config (1165 LOC), security inspector (832), gap analysis (951), simulation (1622) |
| Backend (Phoenix REST + GraphQL) | Working | CRUD + validation via NativeBridge |
| Zig FFI shared library | Working | Real CRUD + validate + dispatch, SHA-256 + Ed25519 |
| Idris2 ABI | Working | 8 genuine proofs (no believe_me) |
| VeriSimDB integration | Working | Remote client with JSONL local fallback |
| Auth (JWT) | Partial | Plug module present, no token refresh/revocation/login UI |
| Simulation mode | Working | Packet sim, build sim, what-if, supply chain, async sessions |
| WebSocket | Partial | Socket.res exists, no live channel logic |
| VeriSimDB as primary store | Not started | Client exists for audit; needs stack/user/settings CRUD |
| miniKanren engine | Not started | Design complete |
| Post-quantum crypto | Not started | Module scaffolded only |

**Architectural Decision (2026-03-23):** All Stapeln data uses VeriSimDB, not PostgreSQL. Port 8093, volume `stapeln-verisimdb-data`. PostgreSQL container stopped; Ecto layer to be removed.

---

## Phase 1: Design & Specifications (COMPLETE)

- [x] ReScript-TEA architecture (Model, Msg, Update, View)
- [x] Three-page UI design (Paragon, Cisco, Settings)
- [x] WCAG 2.3 AAA accessibility specifications
- [x] GraphQL schema with a11y metadata
- [x] VeriSimDB integration spec (6 modalities)
- [x] A2ML integration spec (attested documentation)
- [x] K9-SVC integration spec (self-validating configs)
- [x] miniKanren security reasoning engine design
- [x] OWASP ModSecurity + firewall configuration spec
- [x] Ephemeral pinhole design (auto-expiring firewall rules)
- [x] UX Manifesto ("If you have to read the manual, we failed")
- [x] Security stack audit (identified 47% -> 100% path)
- [x] 14 Architecture Decision Records (ADRs)

## Phase 2: Frontend Implementation (COMPLETE — 100%)

- [x] PortConfigPanel.res (1165 lines) — visual port state toggles, ephemeral duration, countdown, risk indicators
- [x] SecurityInspector.res (832 lines) — score display, vulnerability list, quick checks, CVE display
- [x] GapAnalysis.res (951 lines) — gap detection, severity prioritization, auto-fix buttons, provenance
- [x] SimulationMode.res (1622 lines) — packet animation, multiple types, node rendering, stats, event log
- [x] PipelineDesigner — 3-panel node-graph editor with SVG canvas, bezier connections, minimap, context menus, drag-drop, 6 templates, code generation preview
- [x] App.res integration — 9 navigation views fully functional
- [x] URL-based routing (AppRouter.res) with back/forward navigation
- [x] Undo/redo system (snapshot-based, 50-depth cap)
- [x] Auto-save (30-second interval with dirty tracking)
- [x] Dark mode (system detection + localStorage persistence)
- [x] Conversational errors (UX Manifesto Rule 4 pattern)
- [x] Import/Export with file picker and error suggestions

## Phase 3: Backend & Security (IN PROGRESS — ~75%)

### Backend Core (DONE)

- [x] Phoenix REST endpoints for stacks and validation
- [x] GraphQL API (Absinthe) at `/api/graphql`
- [x] Shared API boundary (REST/GraphQL route through NativeBridge)
- [x] Zig FFI shared library (real CRUD + validate + dispatch)
- [x] Idris2 ABI with 8 genuine proofs
- [x] Real SHA-256 + Ed25519 in crypto.zig
- [x] VeriSimDB remote client with JSONL fallback
- [x] Runtime boundary established (design plane vs Svalinn/Vordr lifecycle)

### Simulation Engine (DONE)

- [x] Network packet flow simulation (SimulationEngine) — deterministic dry-run
- [x] Container build simulation (BuildSimulator) — layer sizes, times, security
- [x] What-if analysis engine (WhatIfEngine) — compare pipeline variants side-by-side
- [x] Supply chain analyzer (SupplyChainAnalyzer) — SLSA levels, provenance, trust boundaries
- [x] Simulation server (SimulationServer) — async session management GenServer
- [x] Simulation REST API — 8 endpoints (/simulations/build, what-if, suggest, supply-chain, sessions CRUD)
- [x] NativeBridge integration — build_simulate, what_if, supply_chain_analyze
- [x] Scenario suggestion engine — auto-detects improvement opportunities
- [x] VeriSimDB audit logging for all simulation types

### Authentication (PARTIAL)

- [x] JWT + Plug module present
- [ ] Token refresh and revocation
- [ ] Session management
- [ ] Login UI screen
- [ ] PAM integration

### VeriSimDB as Primary Store (NOT STARTED)

- [ ] Extend VeriSimDB client for stack CRUD
- [ ] Extend for user and settings CRUD
- [ ] Remove Ecto/PostgreSQL layer
- [ ] Migrate existing GenServer state to VeriSimDB

### miniKanren Security Engine (NOT STARTED)

- [ ] Guile Scheme + miniKanren library setup
- [ ] 10+ security rules (SSH exposure, root user, unencrypted traffic, etc.)
- [ ] CVE feed sync (NIST NVD API)
- [ ] OWASP Top 10 rules
- [ ] CIS Benchmark rules

### Firewall & WAF (NOT STARTED)

- [ ] OWASP ModSecurity CRS (Svalinn gateway)
- [ ] firewalld/nftables integration
- [ ] Ephemeral pinhole scripts
- [ ] Port conflict detection with auto-fix

## Phase 4: Integration & Testing (NOT STARTED)

- [ ] Frontend-backend API wiring (data model alignment)
- [ ] WebSocket live channel push/receive
- [ ] miniKanren-Elixir IPC (S-expression parsing)
- [ ] VeriSimDB end-to-end (all 6 modalities)
- [ ] Firewall-UI sync
- [ ] **Container-Hater Test** (3-tier app in <30 min, no docs)
- [ ] Accessibility testing (screen reader, keyboard-only, braille, contrast)
- [ ] Performance testing (100+ container stacks)
- [ ] Security penetration testing

## Phase 5: Post-Quantum Crypto Upgrades (NOT STARTED)

### Month 1: Hybrid Classical + PQ

- [ ] Dilithium5-AES (ML-DSA-87) alongside Ed25519
- [ ] Kyber-1024 (ML-KEM-1024) for TLS key exchange
- [ ] SPHINCS+ as fallback option

### Month 2: Full PQ Migration

- [ ] Dilithium5 as primary signer
- [ ] HTTP/3 + QUIC migration
- [ ] SHAKE3-512 hashing
- [ ] Argon2id passwords (512 MiB, 8 iterations)
- [ ] XChaCha20-Poly1305 bundle encryption

## Phase 6: 1.0 Release (Target: Q3 2026)

- [ ] All phases complete
- [ ] 100% test coverage (critical paths)
- [ ] WCAG 2.3 AAA verified
- [ ] Security audit passed
- [ ] Container-hater test passed
- [ ] Documentation complete
- [ ] Tutorial videos published

---

## Post-1.0

### v1.1: Advanced Features (Q4 2026)

- [ ] Multi-user collaboration
- [ ] Stack templates marketplace
- [ ] AI-powered optimization suggestions (explanations only)
- [ ] Cost estimation (cloud deployment)
- [ ] Advanced simulation (chaos engineering)

### v1.2: Enterprise Features (Q1 2027)

- [ ] RBAC (Role-Based Access Control)
- [ ] SSO integration
- [ ] Compliance reporting
- [ ] Custom rule engine
- [ ] CI/CD integration

### v2.0: Kubernetes Integration (2027)

- [ ] Kubernetes YAML generation
- [ ] Helm charts and Operators
- [ ] Service mesh integration (Istio, Linkerd)
- [ ] GitOps (FluxCD, ArgoCD)

---

## Key Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| VeriSimDB migration complexity | High | Keep JSONL fallback, migrate incrementally |
| miniKanren performance | Medium | Profile and cache; deterministic is the point |
| Container-hater test fails | Critical | Iterate on UX until pass |
| PQ crypto complexity | High | Hybrid mode first |
| Data model alignment (frontend/backend) | Medium | Shared schema via Zig FFI types |

---

**Last Updated**: 2026-03-29
**Status**: Phase 2 complete, Phase 3 ~75% (backend core + simulation engine done, auth/VeriSimDB primary/miniKanren/firewall pending)
