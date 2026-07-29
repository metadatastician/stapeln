> [!WARNING]
> **SUPERSEDED — this document contains claims falsified by measurement on 2026-07-28.**
> See `STATUS.md` in this repo for measured state, and
> `dev-notes/stapeln-ecosystem-COMPREHENSIVE-SITREP-2026-07-28.md` for full evidence.
> Falsified here: claims ~82% overall, 'Database Integration 100% PostgreSQL' (no ecto/postgrex in mix.exs), and 'Security/Gap views call real API' (they make zero HTTP calls). Retained for history; do not cite.

<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->
<!-- TOPOLOGY.md — Project architecture map and completion dashboard -->
<!-- Last updated: 2026-03-23 -->

# stapeln — Project Topology

## System Architecture

```
                        +-----------------------------------------+
                        |              OPERATOR / ADMIN           |
                        |        (Visual Designer / Drag-and-Drop)|
                        +-------------------+---------------------+
                                            |
                                            v
                        +-----------------------------------------+
                        |         FRONTEND (RESCRIPT TEA)         |
                        |  +-----------+  +-------------------+  |
                        |  | 9 Views   |  | Socket.res        |  |
                        |  | (Tabbed)  |  | (WebSocket)       |  |
                        |  +-----+-----+  +--------+----------+  |
                        |        |    ApiClient     |             |
                        |        |   (REST + WS)    |             |
                        |  +-----v-----+  +--------v----------+  |
                        |  | Lago Grey |  |  Simulation       |  |
                        |  | (Images)  |  |  (Packet Flow)    |  |
                        |  +-----+-----+  +--------+----------+  |
                        |        |  Export: JSON, Compose,       |
                        |        |  K8s YAML, Helm Chart         |
                        +--------|-----------|-+-----------------+
                                 |           | |
                                 v           v v
                        +-----------------------------------------+
                        |          PHOENIX API (ELIXIR)           |
                        |  REST + GraphQL (Absinthe) + WebSocket  |
                        |  +----------+ +----------+ +--------+  |
                        |  | Auth     | | Settings | |Firewall|  |
                        |  | JWT+Plug | | Store    | |Pinholes|  |
                        |  +----------+ +----------+ +--------+  |
                        |  +----------+ +----------+             |
                        |  | Codegen  | | Validator|             |
                        |  | Engine   | | (12 chks)|             |
                        |  +----------+ +----------+             |
                        +-------+--------------+----------+------+
                                |              |          |
                     +----------v---+   +------v----+ +--v-----------------+
                     | NativeBridge |   | Ecto/DB   | | REASONING ENGINE   |
                     | (FFI->Elixir|   | PostgreSQL | | miniKanren         |
                     |  fallback)  |   | or GenSrv  | | Security Rules     |
                     +------+------+   +------+----+  | Gap Analysis       |
                            |                 |       +------+-------------+
                     +------v------+   +------v----+       |
                     | Zig FFI     |   | VeriSimDB |<------+
                     | Shared Lib  |   | Audit Log |
                     | + CLI Bridge|   | JSONL+RPC |
                     | CRUD+Scan+  |   +-----------+
                     | Gap+Dispatch|
                     +------+------+
                            |
                     +------v------+
                     | Idris2 ABI  |
                     | 8 Proofs    |
                     | (Formal)    |
                     +------+------+
                            |
                            v
                     +-----------------------------------------+
                     |           CONTAINER RUNTIME             |
                     |   Podman / Docker / nerdctl + nftables  |
                     |   Post-Quantum: Ed25519 + XMSS hybrid   |
                     +-----------------------------------------+
```

## Completion Dashboard

```
COMPONENT                          STATUS              NOTES
---------------------------------  ------------------  ---------------------------------
FRONTEND (51 ReScript modules, 0 errors, 0 warnings)
  Frontend UI (9 views)            #########.  92%     9 tabs inc. Pipeline Designer; dark mode, undo/redo, auto-save
  Frontend-Backend Wiring          #########.  90%     REST proxy wired; security/gap views call real API; auto-trigger
  Pipeline Designer (NEW)          #########.  90%     3-panel node-graph: canvas, palette, output; 6 templates
  Lago Grey Designer               #######...  70%     Catalog + editor; export not fully wired
  Drag-and-Drop Canvas             ########..  85%     Snap-to-grid, full undo/redo stack (50-depth), bezier connections
  Conversational Errors (NEW)      #########.  90%     UX Manifesto Rule 4; [Fix It] buttons on all API error paths
  WebSocket Integration            #####.....  50%     Socket.res exists; no channel push/receive logic
  URL Routing (NEW)                ##########  100%    AppRouter: URL sync, back/forward, 404 page

BACKEND & API
  Phoenix API (REST+GQL+WS)        #########.  92%     CRUD + validation + security-scan + gap-analysis all verified
  Auth (JWT + Plug)                ######....  60%     Module exists; no session/token refresh/revoke; no login UI
  Settings Persistence             ########..  85%     DbStore auto-switches GenServer↔PostgreSQL
  Firewall Config                  #####.....  50%     Schema present; nftables integration absent
  Database Integration             ##########  100%    PostgreSQL via Podman; migrations run; CRUD verified
  Codegen Engine                   ########..  80%     Containerfile + compose output works

SECURITY & ANALYSIS
  Security Inspector               #########.  90%     Real vulns from backend; miniKanren + checks + ports; empty state UX
  Gap Analysis                     #########.  90%     Real gaps from backend; 8 checks; fix commands; empty state UX
  Security Reasoning (miniKanren)  #######...  70%     Port analysis + db vulns working; KeyError fixed
  Post-Quantum Crypto              ###.......  30%     Module scaffolded; no real XMSS implementation
  Stack Validator                  #########.  90%     12 checks verified returning real findings with scores

SIMULATION & EXPORT
  Simulation Mode                  #######...  70%     Packet flow UI fully renders; no real backend simulation
  Export / Import                  ########..  80%     JSON + compose; working file picker→TEA dispatch; error recovery

ABI / FFI
  Idris2 ABI (Formal Proofs)       #########.  90%     8 genuine proofs, no believe_me, 5 postulates
  Zig FFI                          ########..  80%     CRUD + validate + dispatch; real SHA-256 + Ed25519

DATA & DOCS
  VeriSimDB Integration            ######....  60%     JSONL fallback + remote client; no query UI
  Documentation                    ########..  80%     STATUS.md truth-aligned; TOPOLOGY.md updated 2026-03-23

---------------------------------------------------------------------------
OVERALL:                           ########..  ~82%    End-to-end verified: frontend→proxy→backend→PostgreSQL
```

## Key Dependencies

```
Frontend (ReScript-TEA)
    |
    +--> ApiClient --> Phoenix REST + GraphQL --> NativeBridge --> Zig FFI
    |                       |                         |               |
    +--> Socket.res --> Phoenix Channels              |          Idris2 ABI
    |                       |                         |
    |                       +--> Auth (JWT + Plug)    +--> Elixir GenServer
    |                       |                         |    (fallback stores)
    |                       +--> SecurityScanner -----+
    |                       |        |                |
    |                       |        v                +--> Ecto + PostgreSQL
    |                       |   miniKanren Engine     |    (conditional)
    |                       |                         |
    |                       +--> GapAnalyzer          +--> VeriSimDB
    |                       |                              (audit trail)
    |                       +--> SettingsStore
    |                       |
    |                       +--> Codegen Engine
    |                       |
    |                       +--> Firewall (pinholes + nftables)
    |
    +--> Export: JSON, Compose, K8s, Helm
    |
    +--> Simulation --> Packet Flow Engine
```

## Boundary Contract

- `stapeln/backend` is the **design/control plane** for stack definitions and validation reports.
- `container-stack/svalinn` + `container-stack/vordr` are the **runtime plane** for container lifecycle operations.
- `container-stack/rokur` is the planned secrets/policy gate for runtime operations before container start.

## Update Protocol

This file is maintained by both humans and AI agents. When updating:

1. **After completing a component**: Change its bar and percentage
2. **After adding a component**: Add a new row in the appropriate section
3. **After architectural changes**: Update the ASCII diagram
4. **Date**: Update the `Last updated` comment at the top of this file

Progress bars use: `#` (filled) and `.` (empty), 10 characters wide.
Percentages: 0%, 10%, 20%, ... 100% (in 10% increments).
