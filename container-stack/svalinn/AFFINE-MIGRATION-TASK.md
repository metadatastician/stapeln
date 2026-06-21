<!-- SPDX-License-Identifier: MPL-2.0 -->
# Task: complete the svalinn ReScript → AffineScript/typed-wasm migration (verified)

> **Run this with Claude Code in a local CLI that has the toolchain installed.**
> The cloud sandbox cannot build/run AffineScript (no OCaml/opam, opam repo
> + wolfi base off its network allowlist), so the cutover was deliberately
> NOT done there. Locally you can actually verify — that is the whole point.

## Objective

Finish migrating `container-stack/svalinn` off ReScript onto AffineScript
(compiles to typed WasmGC via `hyperpolymath/affinescript`; ABI from
`hyperpolymath/typed-wasm`), hosted by Deno. **Nothing stays in ReScript.**
Do not claim done until every verification gate below passes locally.

Work on branch `claude/stapeln-maintenance-followup-iEUKy` (PR #46, draft).
Commit per logical module; push; keep the PR draft until all gates pass.

## Prerequisites (must exist locally)

- `opam` + OCaml ≥ 5.1, `dune` ≥ 3.14, `m4`, `git`
- `cargo` (Rust) — for `typed-wasm`
- `deno`
- `docker` (or `podman`) — for the container build gate
- Network access to `github.com` (clones affinescript + typed-wasm)

## Toolchain bring-up (do once)

```bash
# affinescript compiler — PIN must match Containerfile + svalinn-affine-build.yml
git clone https://github.com/hyperpolymath/affinescript.git /tmp/affinescript
cd /tmp/affinescript && git checkout 58dc2a0bdfcd78bcc3448fe5a1785e2128adc005
# Carry the vetted WASM cross-module constructor-linking fix until it lands
# upstream in affinescript (then drop this apply + bump the pin to the merged SHA):
git apply <stapeln>/container-stack/svalinn/patches/affinescript-wasm-ctor-link.patch
opam install --deps-only -y . && eval "$(opam env)" && dune build --release
export AFFINESCRIPT_BIN=/tmp/affinescript/_build/install/default/bin/affinescript

# typed-wasm (ABI/conventions) — pin matches Containerfile
git clone https://github.com/hyperpolymath/typed-wasm.git /tmp/typed-wasm
cd /tmp/typed-wasm && git checkout e90e2d1a307c33d594d54065c902500da327977c
cargo build --release --locked
```

Read these upstream files before porting (they define syntax/stdlib/limits):
`/tmp/affinescript/examples/*.affine`, `stdlib/{prelude,string,io,result,Network,Crypto}.affine`,
`COMPILER-CAPABILITIES.md`, `KNOWN-ISSUES.md`, `affinescript-deno-test/`
(the `@hyperpolymath/affine-js` Deno bridge contract).

## Architecture & conventions (already established — keep consistent)

- **Boundary:** pure logic/types live in `.affine`; all I/O (sockets,
  fetch, env, fs, crypto, JSON value type) is host-side in
  `src/host/affine_host.js` (plain JS — svalinn policy **bans TypeScript**;
  JS allowed for Deno glue).
- **JSON:** `.affine` has no JSON type. `src/host/Json.affine` declares
  `extern` accessors; the host owns a handle arena (`0` = null/absent).
  Re-use this protocol for all JSON.
- **AffineScript notes:** Rust-like (`struct`/`enum`/`fn`/`pub fn`/`match`/
  `if`/`while`/`let`, generics `<T>`, `[T]`, `Option`/`Result` in prelude,
  `len`, `string_sub`, `string_find`, `int_to_string`, `float_to_string`).
  No async, no JS interop. `module Name;` header; `use Other;` imports;
  `pub extern fn` = host import. **Pitfall:** prelude defines
  `Option::None`, so don't name an enum variant `None` (we used `NoAuth`).
- Every file starts with `// SPDX-License-Identifier: MPL-2.0`.
- One WASM module per top-level `.affine`; host loads by basename.

## Already done (11/31 — do NOT redo, mirror their style)

`src/host/Json.affine`, `src/Main.affine`, `src/gateway/GatewayTypes.affine`,
`src/policy/PolicyEngine.affine`, `src/gateway/SecurityHeaders.affine`,
`src/gateway/RateLimiter.affine`, `src/gateway/Metrics.affine`,
`src/auth/AuthTypes.affine`, `src/auth/Authz.affine`,
`src/vordr/VordrTypes.affine`, `src/vordr/Client.affine`.
Build pipeline (`Containerfile` 4-stage, `deno.json`, `scripts/affine-build.sh`)
and host bridge are in place. CI gate: `.github/workflows/svalinn-affine-build.yml`.

## Remaining work

Port each, applying the boundary rule (pure → `.affine`; I/O → host extern):

1. `src/gateway/Gateway.res` (≈1219 LOC, the router/orchestrator) →
   `src/gateway/Gateway.affine` + host route wiring. Pure: routing
   table, request/response shaping, error envelopes. Host: actual
   `Deno.serve` dispatch (already host-owned) — expose `pub fn`
   handlers per route and call them from `affine_host.js`.
2. `src/mcp/McpTypes.res` → `McpTypes.affine` (pure types).
3. `src/mcp/McpClient.res`, `src/mcp/Server.res`, `src/mcp/Tools.res` →
   `.affine` pure protocol shaping; transport in host.
4. `src/validation/Validation.res` → `Validation.affine` pure field
   accessors/policy logic; **Ajv schema validation is host-side**
   (add `extern fn ajv_validate(schema_id, json_handle) -> ...`).
5. `src/bridge/SelurBridge.res` → `SelurBridge.affine` (+ host transport).
6. `src/bindings/{Deno,Fetch,Hono}.res` → delete; their role is
   subsumed by `affine_host.js`. Remove all `.res` imports.
7. `src/vordr/Client.res` host wiring: implement the Fetch POST +
   `/health` ping in `affine_host.js` calling the existing
   `Client.affine` envelope/parse functions.
8. `src/auth/*` host wiring: implement JWT signature verify (WebCrypto
   `crypto.subtle.importKey/verify`), JWKS fetch+cache, OAuth2 token/
   refresh/introspect/revoke, secure random, base64url in
   `affine_host.js`, calling `Authz.affine` for every decision.
9. `ui/src/*.res` (browser ReScript) → `.affine` compiled to WASM for
   the browser (see upstream `affinescript-dom`/`affinescript-vite`),
   or, if that path is not viable, raise it explicitly — do not silently
   leave ReScript.
10. `tests/integration_test.res` → AffineScript tests via
    `affinescript-deno-test` (`*_test.affine`, `pub fn test_* -> Bool`).

## Cutover (ONLY after every gate below is green)

- Delete every remaining `.res` under `container-stack/svalinn`.
- Confirm `deno.json` has no rescript tasks/imports (already done).
- Confirm `Containerfile` ENTRYPOINT is `src/host/affine_host.js`
  (already done). Update `.gitignore` if any new dirs need tracking.

## Verification gates (ALL must pass locally — this is "verified")

1. `find container-stack/svalinn/src -name '*.affine' -print0 | \
    xargs -0 -n1 -I{} "$AFFINESCRIPT_BIN" compile {} -o /tmp/x.wasm`
   → every module compiles, exit 0. Fix codegen issues; consult
   `KNOWN-ISSUES.md` for compiler-side bugs/workarounds.
2. `cd container-stack/svalinn && deno check src/host/affine_host.js`
   → no errors.
3. `cd container-stack/svalinn && docker build -f Containerfile -t svalinn:affine .`
   → image builds (exercises all 4 stages incl. typed-wasm).
4. Run it and smoke every implemented route:
   ```bash
   docker run -d -p 8000:8000 --name svalinn-aff svalinn:affine
   curl -fsS localhost:8000/healthz
   curl -fsS localhost:8000/metrics | grep svalinn_requests_total
   curl -fsS -XPOST localhost:8000/v1/policy/evaluate \
     -d '{"policy":{"version":1,"requiredPredicates":[],"allowedSigners":[],"logQuorum":0,"mode":"permissive"},"attestations":[]}'
   # plus the gateway/auth/vordr/mcp routes once ported
   ```
   All return expected status/body; no 501 for ported routes.
5. Push; the `svalinn AffineScript build` CI check on PR #46 is green
   (it is intentionally blocking).
6. No `.res` remain under `container-stack/svalinn`; SonarCloud 0 new
   issues; PR description module table updated to 31/31.

## Definition of done

All 6 gates green, PR #46 marked ready (not draft), zero `.res` in
svalinn, and a short note in the PR stating which gates were run and
their results. If the alpha compiler cannot compile a construct, record
the blocker explicitly in the PR — do not fake completion or silently
keep ReScript.
