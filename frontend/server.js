// SPDX-License-Identifier: PMPL-1.0-or-later
// server.js - Deno development server with API proxy to Phoenix backend

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { serveDir } from "https://deno.land/std@0.224.0/http/file_server.ts";

const PORT = 8000;
const BACKEND_URL = Deno.env.get("STAPELN_BACKEND_URL") || "http://localhost:4000";

console.log(`🏔️ stapeln development server`);
console.log(`Frontend: http://localhost:${PORT}`);
console.log(`Backend:  ${BACKEND_URL}`);

serve(
  async (req) => {
    const url = new URL(req.url);

    // Proxy /api/* requests to the Phoenix backend
    if (url.pathname.startsWith("/api")) {
      try {
        const backendUrl = `${BACKEND_URL}${url.pathname}${url.search}`;
        const headers = new Headers(req.headers);
        headers.delete("host"); // Don't forward the host header

        const backendResp = await fetch(backendUrl, {
          method: req.method,
          headers,
          body: req.method !== "GET" && req.method !== "HEAD" ? req.body : undefined,
        });

        // Forward the backend response with CORS headers
        const respHeaders = new Headers(backendResp.headers);
        respHeaders.set("access-control-allow-origin", "*");
        respHeaders.set("access-control-allow-methods", "GET, POST, PUT, DELETE, OPTIONS");
        respHeaders.set("access-control-allow-headers", "content-type, authorization");

        return new Response(backendResp.body, {
          status: backendResp.status,
          headers: respHeaders,
        });
      } catch (err) {
        console.error(`Backend proxy error: ${err.message}`);
        return new Response(
          JSON.stringify({ error: "Backend unavailable", message: err.message }),
          { status: 502, headers: { "content-type": "application/json" } }
        );
      }
    }

    // Handle CORS preflight for API routes
    if (req.method === "OPTIONS" && url.pathname.startsWith("/api")) {
      return new Response(null, {
        status: 204,
        headers: {
          "access-control-allow-origin": "*",
          "access-control-allow-methods": "GET, POST, PUT, DELETE, OPTIONS",
          "access-control-allow-headers": "content-type, authorization",
          "access-control-max-age": "86400",
        },
      });
    }

    // Serve static files for everything else
    return serveDir(req, {
      fsRoot: ".",
      urlRoot: "",
      enableCors: true,
    });
  },
  { port: PORT }
);
