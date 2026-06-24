# SPDX-License-Identifier: CC-BY-SA-4.0
# Stapeln — Haiku session brief

**Model:** Claude Haiku
**Repo:** `fleet-ecosystem/stapeln` (at `/var/mnt/eclipse/repos/fleet-ecosystem/stapeln`)
**Tasks:** DB-3, C-1, C-3, F-2, F-3
**Prerequisite:** None — run this first

---

## DB-3 — Start VeriSimDB on port 8093

VeriSimDB is stapeln's persistence engine. Check what's available:

```bash
grep -i verisim stapeln.toml
ls container-stack/
find . -name "*verisimdb*" -o -name "*verisim*Containerfile*" 2>/dev/null
```

If a Containerfile exists, build and start it:

```bash
podman build -t verisimdb-stapeln -f <path-to-Containerfile> .
podman run -d --name verisimdb-stapeln -p 8093:8080 \
  -v stapeln-verisimdb-data:/data verisimdb-stapeln
curl http://localhost:8093/health
```

If no Containerfile exists in this repo, check:
- `/var/mnt/eclipse/repos/verisimdb/`
- `/var/mnt/eclipse/repos/developer-ecosystem/`

For a pre-built image. Do NOT invent an implementation.

Find where the app reads the URL: `grep -r VERISIMDB backend/config/`
Set `VERISIMDB_URL=http://localhost:8093` in the appropriate config file.

Verify `DbStore.available?()` now returns true by running:
```bash
cd backend && mix run -e "IO.inspect(Stapeln.DbStore.available?())"
```

---

## C-1 — Create `docs/READINESS.md`

`just crg-grade` looks for `**Current Grade:** X` in `READINESS.md`. Create it:

```markdown
# SPDX-License-Identifier: CC-BY-SA-4.0
# Stapeln — Component Readiness Grade

**Current Grade:** D

## D-floor status (as of 2026-04-25)

Blockers to C:
- VeriSimDB migration incomplete (GenServer fallback still live)
- Weak README coverage in backend/lib/ subdirectories
- No Rust test signal in push/PR CI

## CRG history

| Date | Grade | Notes |
|------|-------|-------|
| 2026-04-18 | D | Demoted from C per docs/governance/CRG-AUDIT-2026-04-18.adoc |
| 2026-04-04 | C | After blitz: 314+ tests added |
```

Verify: `just crg-grade` must output `D`.

---

## C-3 — README files for `backend/lib/` subdirectories

Find missing READMEs:
```bash
for d in backend/lib/stapeln/*/; do
  [ -f "$d/README.md" ] || echo "MISSING: $d"
done
```

For each missing one, create a one-paragraph `README.md` describing what the directory contains. SPDX header required. At minimum cover:

- `backend/lib/stapeln/auth/` — JWT token generation and verification
- `backend/lib/stapeln/kanren/` — miniKanren constraint engine for pipeline validation
- `backend/lib/stapeln/simulation/` — build/what-if/supply-chain simulation engines

---

## F-2 — Fix missing `Tour.res.js`

`frontend/src/Tour.res` exists but has no compiled output. Find exported names:
```bash
grep "^let\|^and " frontend/src/Tour.res | head -20
```

If rescript build works: `cd frontend && npm install && rescript build`

Otherwise create a minimal stub `frontend/src/Tour.res.js` that exports no-ops for each exported name. SPDX header required.

---

## F-3 — Add `Containerfile`

The aspect test SKIPs the Chainguard check. Create `Containerfile` at repo root:

```dockerfile
# SPDX-License-Identifier: CC-BY-SA-4.0
FROM cgr.dev/chainguard/elixir:latest AS build
WORKDIR /app
COPY backend/ .
RUN mix deps.get --only prod && mix compile && mix release

FROM cgr.dev/chainguard/elixir:latest
COPY --from=build /app/_build/prod/rel/stapeln ./
CMD ["./bin/stapeln", "start"]
```

Verify: `bash tests/aspect/aspect_tests.sh` — Containerfile check must PASS (not SKIP).

---

## Done

```bash
just e2e   # must be 0 failures
```

Commit:
```
fix(stapeln): Haiku session — VeriSimDB start, READINESS, READMEs, Tour stub, Containerfile

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>
```

Push to `origin main`.
