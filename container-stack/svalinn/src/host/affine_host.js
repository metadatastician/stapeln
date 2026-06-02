// SPDX-License-Identifier: MPL-2.0
// affine_host.js — Deno host bridge for the AffineScript/typed-wasm build.
//
// Plain JavaScript (svalinn language policy: JS is permitted for Deno-API
// glue; TypeScript is not). AffineScript compiles to typed WasmGC: WASM
// cannot own sockets, env, the filesystem, crypto or a JSON value type, so
// the host supplies every `pub extern fn` declared in the .affine sources,
// owns the HTTP listener, and marshals values across the boundary. WASM
// loading + value marshalling reuse the upstream @hyperpolymath/affine-js
// bridge, exactly as affinescript-deno-test does.
//
// Phase 1 wires the policy-evaluation path (Main.handle_evaluate). Routes
// backed by not-yet-ported modules return 501 until their .affine ports
// land (see the migration status in the PR description).

import { AffineModule } from "@hyperpolymath/affine-js";

// --- Host JSON arena -------------------------------------------------------
// `Json.affine` references JSON values by opaque integer handle. The host
// keeps the real values here; 0 is reserved for null / absent / error.
const arena = [null];
function put(v) {
  arena.push(v);
  return arena.length - 1;
}
const get = (h) => arena[h] ?? null;

function kind(v) {
  if (v === null || v === undefined) return 0;
  if (typeof v === "boolean") return 1;
  if (typeof v === "number") return 2;
  if (typeof v === "string") return 3;
  if (Array.isArray(v)) return 4;
  if (typeof v === "object") return 5;
  return 0;
}

// Host imports satisfying the .affine `extern` declarations. `affine-js`
// passes/returns AffineScript values; strings and ints marshal directly.
function hostImports() {
  return {
    // Json.affine
    json_parse: (t) => {
      try { return put(JSON.parse(t)); } catch { return 0; }
    },
    json_kind: (h) => kind(get(h)),
    json_as_bool: (h) => (get(h) === true),
    json_as_int: (h) => Math.trunc(Number(get(h) ?? 0)),
    json_as_string: (h) => String(get(h) ?? ""),
    json_get: (h, k) => {
      const o = get(h);
      return o && typeof o === "object" && !Array.isArray(o) && k in o
        ? put(o[k]) : 0;
    },
    json_len: (h) => {
      const a = get(h);
      return Array.isArray(a) ? a.length : 0;
    },
    json_at: (h, i) => {
      const a = get(h);
      return Array.isArray(a) && i >= 0 && i < a.length ? put(a[i]) : 0;
    },
    json_new_object: () => put({}),
    json_new_array: () => put([]),
    json_set: (o, k, v) => {
      const obj = get(o);
      if (obj && typeof obj === "object") obj[k] = get(v);
    },
    json_push: (a, v) => {
      const arr = get(a);
      if (Array.isArray(arr)) arr.push(get(v));
    },
    json_of_bool: (v) => put(v),
    json_of_int: (v) => put(Math.trunc(v)),
    json_of_string: (v) => put(v),
    json_stringify: (h) => JSON.stringify(get(h) ?? null),

    // io.affine builtins used by the ported modules
    read_file: (p) => {
      try { return { ok: Deno.readTextFileSync(p) }; }
      catch (e) { return { err: String(e) }; }
    },
    getenv: (n) => Deno.env.get(n) ?? null,

    // Wall-clock epoch milliseconds for RateLimiter.affine.
    now_ms: () => Date.now(),

    // WASI stub: AffineScript codegen imports fd_write unconditionally.
    fd_write: (_fd, _iovs, _n, _ret) => 0,
  };
}

const WASM_DIR = new URL("../../dist/wasm/", import.meta.url);

async function loadModule(name) {
  const bytes = await Deno.readFile(new URL(`${name}.wasm`, WASM_DIR));
  return await AffineModule.instantiate(bytes, hostImports());
}

// --- HTTP listener (host-owned) -------------------------------------------

const PORT = Number(Deno.env.get("SVALINN_PORT") ?? "8000");

const main = await loadModule("Main");
const secHeaders = await loadModule("SecurityHeaders");
const rateLimiter = await loadModule("RateLimiter");
const metrics = await loadModule("Metrics");

if (main.call("serve") !== 0) {
  console.error("svalinn: Main.serve() reported a fatal wiring error");
  Deno.exit(1);
}

// Host-owned mutable state the .affine decision/format cores operate on.
const rlConfig = rateLimiter.call("default_config");
const rlState = new Map(); // clientIp -> { count, windowStart }
const counters = { requestsTotal: 0, errorsTotal: 0, authFailuresTotal: 0 };
const hist = {
  buckets: get(metrics.call("default_buckets")),
  counts: [0, 0, 0, 0, 0, 0],
  sum: 0,
  count: 0,
};
// Gauges the host mutates in place (the Vordr container-count refresh,
// a tracked follow-up, will update gauges.containersActive).
const gauges = { containersActive: 0 };

// Apply the .affine security-header set to a Response.
function withSecurityHeaders(resp) {
  const hdrs = get(secHeaders.call("security_headers"));
  for (const [k, v] of Object.entries(hdrs)) resp.headers.set(k, v);
  return resp;
}

function jsonResponse(handle, status = 200) {
  return withSecurityHeaders(
    new Response(JSON.stringify(get(handle) ?? null), {
      status,
      headers: { "content-type": "application/json" },
    }),
  );
}

function clientIp(req) {
  const xff = req.headers.get("X-Forwarded-For");
  if (xff) return xff.split(",")[0].trim();
  return req.headers.get("X-Real-IP") ?? "unknown";
}

function rateLimit(req) {
  const ip = clientIp(req);
  const prev = rlState.get(ip) ?? { count: 0, windowStart: 0 };
  const d = get(
    rateLimiter.call("check", rlConfig, prev.count, prev.windowStart, Date.now()),
  );
  rlState.set(ip, { count: d.count, windowStart: d.window_start });
  return d;
}

Deno.serve({ port: PORT }, async (req) => {
  const url = new URL(req.url);
  counters.requestsTotal += 1;

  const rl = rateLimit(req);
  if (!rl.allowed) {
    counters.errorsTotal += 1;
    const resp = jsonResponse(
      put({ error: "Rate limit exceeded", retryAfter: rl.retry_after }),
      429,
    );
    resp.headers.set("Retry-After", String(rl.retry_after));
    resp.headers.set("X-RateLimit-Remaining", "0");
    return resp;
  }

  if (url.pathname === "/healthz") {
    return jsonResponse(put({ status: "ok" }));
  }

  if (url.pathname === "/metrics") {
    const body = metrics.call(
      "format_prometheus",
      counters.requestsTotal,
      counters.errorsTotal,
      counters.authFailuresTotal,
      put(hist.buckets),
      put(hist.counts),
      hist.sum,
      hist.count,
      gauges.containersActive,
    );
    return withSecurityHeaders(
      new Response(body, { headers: { "content-type": "text/plain; version=0.0.4" } }),
    );
  }

  if (url.pathname === "/v1/policy/evaluate" && req.method === "POST") {
    const text = await req.text();
    const bodyHandle = put(text === "" ? {} : JSON.parse(text));
    const respHandle = main.call("handle_evaluate", bodyHandle);
    return jsonResponse(respHandle);
  }

  // Routes backed by not-yet-ported .affine modules (auth, mcp, vordr,
  // gateway router, …). See PR description for per-module status.
  counters.errorsTotal += 1;
  return jsonResponse(
    put({ code: "not_implemented", message: `${url.pathname} pending .affine port` }),
    501,
  );
});
