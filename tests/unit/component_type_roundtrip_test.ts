// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Round-trip tests for componentType encode/decode — stapeln#42.
//
// WHY THIS FILE IMPORTS THE COMPILED OUTPUT RATHER THAN MIRRORING IT.
//
// The encode table lives in Model.res and the decode table in
// DesignFormat.res. They are two independent string tables that MUST agree,
// and nothing enforces that: the encoder is a switch over a variant, so the
// compiler forces every case to be handled, but the decoder is a match over
// strings with a catch-all, so it compiles perfectly while silently losing
// data.
//
// A test that restated the tables here would pass while the real ones
// diverged — it would be testing its own copy. So this imports
// `src/*.res.js`, the actual artefacts `index.html` loads.
//
// The defect being guarded (stapeln#42): the decoder's catch-all was
// `| _ => None`, and because a component only decodes when id, type, position
// and config are ALL Some, an unrecognised type made the WHOLE COMPONENT
// vanish — silently, no error. Opening a design saved by a newer build lost
// boxes and told nobody.

import { assert, assertEquals } from "jsr:@std/assert";

// Model.res.js runs initAuthState() at module top level, which reads
// window.localStorage — a browser dependency executed on IMPORT, not on call.
// Deno 2 has no `window`, so the module throws before any test can run.
//
// A minimal stub is installed here and the real modules are then imported
// DYNAMICALLY, because static imports are hoisted above any statement and
// would execute before the stub exists.
//
// This is a harness detail, not a workaround for a defect: the module is
// browser code and legitimately expects a browser. Worth knowing that
// importing Model.res.js has a side effect at all.
// deno-lint-ignore no-explicit-any
(globalThis as any).window = {
  localStorage: {
    getItem: (_k: string) => null,
    setItem: (_k: string, _v: string) => {},
    removeItem: (_k: string) => {},
  },
};

const { componentTypeToString } = await import(
  "../../frontend/src/Model.res.js"
);
const { componentFromJson } = await import(
  "../../frontend/src/DesignFormat.res.js"
);

// Every componentType the designer can produce, as the string that actually
// travels on the wire. These are DISPLAY names, not variant names, and they
// are irregular on purpose — the irregularity is the point of testing them:
//
//   "Cerro Torre" / "Lago Grey"  contain a SPACE
//   "selur" / "nerdctl"          are lowercase
//   "Vörðr"                      is NOT ASCII (U+00F6 ö, U+00F0 ð)
//
// These strings are the on-disk format of every saved design. Changing one
// breaks every file already written.
const WIRE_NAMES = [
  "Cerro Torre",
  "Lago Grey",
  "Svalinn",
  "selur",
  "Vörðr",
  "Rokur",
  "Podman",
  "Docker",
  "nerdctl",
  "Volume",
  "Network",
] as const;

/** A minimal component JSON object of the shape DesignFormat expects. */
function componentJson(type_: string) {
  return {
    id: "c-1",
    type: type_,
    position: { x: 10.5, y: 20.0 },
    config: {},
  };
}

Deno.test("every wire name decodes, and re-encodes to itself", () => {
  for (const name of WIRE_NAMES) {
    const decoded = componentFromJson(componentJson(name));

    assert(
      decoded !== undefined,
      `"${name}" failed to decode — the component would be SILENTLY LOST`,
    );

    const reencoded = componentTypeToString(decoded.componentType);
    assertEquals(
      reencoded,
      name,
      `"${name}" did not survive the round-trip (got "${reencoded}") — ` +
        `Model.res and DesignFormat.res disagree about this name`,
    );
  }
});

Deno.test("the non-ASCII name survives byte-for-byte", () => {
  // Vörðr is the one a stray latin-1 decode, a naive downcase, or a
  // slug-ifying "clean-up" would mangle. Compare codepoints, not just
  // equality, so a failure says WHAT changed.
  const decoded = componentFromJson(componentJson("Vörðr"));
  assert(decoded !== undefined, "Vörðr failed to decode");

  const out = componentTypeToString(decoded.componentType);
  assertEquals(out, "Vörðr");
  assertEquals([...out].map((c) => c.codePointAt(0)), [
    0x56, // V
    0xF6, // ö
    0x72, // r
    0xF0, // ð
    0x72, // r
  ]);
});

Deno.test("an UNKNOWN type is preserved, not deleted — stapeln#42", () => {
  // The regression this file exists for. Before the fix this returned
  // undefined and the component disappeared from the design with no error.
  const decoded = componentFromJson(componentJson("SomeFutureComponent"));

  assert(
    decoded !== undefined,
    "an unrecognised component type was DROPPED — this is stapeln#42 " +
      "regressing: user data is being destroyed silently",
  );
  assertEquals(decoded.id, "c-1", "the rest of the component survived intact");
});

Deno.test("an unknown type round-trips as the name it was saved with", () => {
  // Forward compatibility: a design saved by a newer build, opened and
  // re-saved by an older one, must not have its unknown components rewritten
  // into something else.
  const original = "SomeFutureComponent";
  const decoded = componentFromJson(componentJson(original));
  assert(decoded !== undefined);

  assertEquals(
    componentTypeToString(decoded.componentType),
    original,
    "re-saving rewrote a component type this build did not understand",
  );
});

Deno.test("a component with NO type field still fails to decode", () => {
  // The control, and the distinction that matters: a missing "type" is a
  // MALFORMED document, not a version skew. It must still be rejected —
  // otherwise this test file would pass simply because nothing is ever
  // rejected any more.
  const decoded = componentFromJson({
    id: "c-1",
    position: { x: 0.0, y: 0.0 },
    config: {},
  });

  assertEquals(
    decoded,
    undefined,
    "a component with no type field must NOT decode — accepting it would " +
      "mean this suite passes by accepting everything",
  );
});
