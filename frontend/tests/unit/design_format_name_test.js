// SPDX-License-Identifier: MPL-2.0
// design_format_name_test.js - Deno unit tests for the stack-name round trip
// through DesignFormat.res.js (serializeDesign / deserializeDesign).
//
// Exercises the fix for the "every saved stack is named stapeln-stack" bug:
// App.res's serializeForApi used to build a designMetadata with a hardcoded
// `description: ""` and no top-level "name" at all, so the backend's
// `derive_name` (Map.get(params, "name") || non_empty(metadata.description)
// || "stapeln-stack") always fell through to the literal fallback. The fix
// threads the user-editable model.stackName/stackDescription into
// designMetadata and serializeDesign now emits a top-level "name" key.

import { assertEquals } from "jsr:@std/assert@1";

// DesignFormat.res.js transitively imports Model.res.js, whose module-level
// `initialModel` eagerly calls ApiClient.getToken() -> `window.localStorage`
// at import time. Deno 2 has no global `window` (only `globalThis`), so
// importing DesignFormat.res.js throws before any test body runs. This is a
// pre-existing gap unrelated to this fix (Model.res.js isn't touched here
// beyond adding two plain string fields) — shim it so the module can load.
globalThis.window ??= globalThis;

const { serializeDesign, deserializeDesign } = await import("../../src/DesignFormat.res.js");

const emptyCanvas = { components: [], connections: [] };

Deno.test("serializeDesign: emits a top-level 'name' key when the stack has a name", () => {
  const json = serializeDesign(emptyCanvas, {
    version: "1.0",
    created: "2026-08-04T00:00:00.000Z",
    author: "stapeln-editor",
    description: "a real description",
    name: "my-production-stack",
  });
  const parsed = JSON.parse(json);
  assertEquals(parsed.name, "my-production-stack");
  assertEquals(parsed.metadata.description, "a real description");
});

Deno.test("serializeDesign: omits the 'name' key entirely when the stack has no name", () => {
  // Regression guard: Elixir's `Map.get(params, "name") || fallback` treats
  // "" as truthy, so sending `"name": ""` would short-circuit derive_name's
  // fallback chain instead of letting it fall through to
  // metadata.description / "stapeln-stack". The key must be absent, not "".
  const json = serializeDesign(emptyCanvas, {
    version: "1.0",
    created: "2026-08-04T00:00:00.000Z",
    author: "stapeln-editor",
    description: "",
    name: "",
  });
  const parsed = JSON.parse(json);
  assertEquals(Object.prototype.hasOwnProperty.call(parsed, "name"), false);
});

Deno.test("deserializeDesign: round-trips the name back out through metadata.name", () => {
  const json = serializeDesign(emptyCanvas, {
    version: "1.0",
    created: "2026-08-04T00:00:00.000Z",
    author: "stapeln-editor",
    description: "d",
    name: "roundtrip-stack",
  });
  const result = deserializeDesign(json);
  assertEquals(result.TAG, "Ok");
  const [metadata] = result._0;
  assertEquals(metadata.name, "roundtrip-stack");
});

Deno.test("deserializeDesign: defaults name to '' for older documents with no top-level name", () => {
  const legacyJson = JSON.stringify({
    version: "1.0",
    metadata: { created: "2026-08-04T00:00:00.000Z", author: "x", description: "d" },
    canvas: { components: [], connections: [] },
  });
  const result = deserializeDesign(legacyJson);
  assertEquals(result.TAG, "Ok");
  const [metadata] = result._0;
  assertEquals(metadata.name, "");
});
