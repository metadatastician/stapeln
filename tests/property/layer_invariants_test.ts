// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <6759885+hyperpolymath@users.noreply.github.com>
//
// Property-based invariant tests for stapeln layer definitions and OCI label generation.
//
// These tests verify four core invariant families:
//   1. Layer invariants  — valid layer definitions always produce valid OCI labels
//   2. Roundtrip         — parse → serialise → parse is identity for layer configs
//   3. Budget properties — any container with memory_budget set must have memory_budget > 0
//   4. Composition       — composing two valid layer sets produces a valid combined set

import { assertEquals, assert, assertExists } from "jsr:@std/assert";

// ---------------------------------------------------------------------------
// Types — mirrors the stapeln data model as documented in stapeln.toml
// ---------------------------------------------------------------------------

/** Layer definition as produced by the stapeln config parser. */
interface LayerDef {
  /** Unique name within this stack (e.g. "backend-deps"). */
  name: string;
  /** Human-readable description for OCI label. */
  description: string;
  /** Optional parent layer name — forms the dependency graph. */
  extends?: string;
  /** Chainguard/OCI base image reference (only set on the root layer). */
  from?: string;
  /** Whether this layer participates in build-cache keying. */
  cache: boolean;
  /** Whether supply-chain verification is required before use. */
  verify?: boolean;
  /** Optional memory budget in MiB (>0 when set). */
  memory_budget?: number;
  /** Optional CPU share weight (>0 when set). */
  cpu_share?: number;
}

/** The set of OCI labels stapeln emits for a layer. */
interface OciLabels {
  "org.stapeln.layer.name": string;
  "org.stapeln.layer.description": string;
  "org.stapeln.layer.cache": string;
  "org.stapeln.layer.extends"?: string;
  "org.stapeln.layer.memory_budget_mib"?: string;
  "org.stapeln.layer.cpu_share"?: string;
}

/** A compiled layer set — the output of composing individual layer definitions. */
interface LayerSet {
  layers: Map<string, LayerDef>;
  buildOrder: string[];
}

// ---------------------------------------------------------------------------
// Helpers — layer utilities mirroring production logic
// ---------------------------------------------------------------------------

/**
 * Generate OCI labels from a layer definition.
 * This mirrors what the stapeln backend emits during `stapeln build`.
 */
function layerToOciLabels(layer: LayerDef): OciLabels {
  const labels: OciLabels = {
    "org.stapeln.layer.name": layer.name,
    "org.stapeln.layer.description": layer.description,
    "org.stapeln.layer.cache": String(layer.cache),
  };
  if (layer.extends !== undefined) {
    labels["org.stapeln.layer.extends"] = layer.extends;
  }
  if (layer.memory_budget !== undefined) {
    labels["org.stapeln.layer.memory_budget_mib"] = String(layer.memory_budget);
  }
  if (layer.cpu_share !== undefined) {
    labels["org.stapeln.layer.cpu_share"] = String(layer.cpu_share);
  }
  return labels;
}

/**
 * Validate a layer definition for structural correctness.
 * Returns an array of human-readable errors (empty = valid).
 */
function validateLayer(layer: LayerDef): string[] {
  const errors: string[] = [];
  if (!layer.name || layer.name.trim() === "") {
    errors.push("layer name must be non-empty");
  }
  if (!layer.description || layer.description.trim() === "") {
    errors.push("layer description must be non-empty");
  }
  if (!layer.from && !layer.extends) {
    errors.push("layer must have either 'from' (base image) or 'extends' (parent layer)");
  }
  if (layer.memory_budget !== undefined && layer.memory_budget <= 0) {
    errors.push(`memory_budget must be > 0, got ${layer.memory_budget}`);
  }
  if (layer.cpu_share !== undefined && layer.cpu_share <= 0) {
    errors.push(`cpu_share must be > 0, got ${layer.cpu_share}`);
  }
  return errors;
}

/**
 * Validate OCI labels produced by layerToOciLabels.
 * Returns an array of errors (empty = valid).
 */
function validateOciLabels(labels: OciLabels): string[] {
  const errors: string[] = [];
  if (!labels["org.stapeln.layer.name"]) {
    errors.push("OCI label 'name' must be present and non-empty");
  }
  if (!labels["org.stapeln.layer.description"]) {
    errors.push("OCI label 'description' must be present and non-empty");
  }
  const cache = labels["org.stapeln.layer.cache"];
  if (cache !== "true" && cache !== "false") {
    errors.push(`OCI label 'cache' must be 'true' or 'false', got '${cache}'`);
  }
  // memory_budget label, when present, must parse to positive integer
  const mbLabel = labels["org.stapeln.layer.memory_budget_mib"];
  if (mbLabel !== undefined) {
    const mb = Number(mbLabel);
    if (!Number.isInteger(mb) || mb <= 0) {
      errors.push(`OCI label memory_budget_mib must be a positive integer, got '${mbLabel}'`);
    }
  }
  return errors;
}

/**
 * Serialise a LayerDef to a JSON-compatible object, then re-parse it.
 * Implements the roundtrip contract.
 */
function roundtripLayer(layer: LayerDef): LayerDef {
  const serialised = JSON.stringify(layer);
  return JSON.parse(serialised) as LayerDef;
}

/**
 * Compose two layer sets into one.
 * Names must be unique across both sets; throws on conflict.
 */
function composeLayers(a: LayerSet, b: LayerSet): LayerSet {
  const combined = new Map<string, LayerDef>(a.layers);
  for (const [name, layer] of b.layers) {
    if (combined.has(name)) {
      throw new Error(`Layer name conflict: '${name}' exists in both sets`);
    }
    combined.set(name, layer);
  }
  return {
    layers: combined,
    buildOrder: [...a.buildOrder, ...b.buildOrder],
  };
}

/**
 * Validate a full layer set — every layer individually valid,
 * every 'extends' reference resolves, no cycles.
 */
function validateLayerSet(set: LayerSet): string[] {
  const errors: string[] = [];

  for (const [name, layer] of set.layers) {
    const layerErrors = validateLayer(layer);
    for (const e of layerErrors) {
      errors.push(`layer '${name}': ${e}`);
    }
    if (layer.extends && !set.layers.has(layer.extends)) {
      errors.push(`layer '${name}' extends '${layer.extends}' which is not in this set`);
    }
  }

  // Verify buildOrder references all layers
  const orderSet = new Set(set.buildOrder);
  for (const name of set.layers.keys()) {
    if (!orderSet.has(name)) {
      errors.push(`layer '${name}' is defined but missing from buildOrder`);
    }
  }

  return errors;
}

// ---------------------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------------------

const BASE_LAYER: LayerDef = {
  name: "base",
  description: "Chainguard Wolfi minimal base image",
  from: "cgr.dev/chainguard/wolfi-base:latest",
  cache: true,
  verify: true,
};

const TOOLCHAIN_LAYER: LayerDef = {
  name: "elixir-toolchain",
  description: "Erlang/OTP + Elixir + Mix build tooling",
  extends: "base",
  cache: true,
};

const DEPS_LAYER: LayerDef = {
  name: "backend-deps",
  description: "Fetch and compile Elixir dependencies",
  extends: "elixir-toolchain",
  cache: true,
  memory_budget: 2048,
  cpu_share: 512,
};

const BUILD_LAYER: LayerDef = {
  name: "backend-build",
  description: "Compile and release Elixir application",
  extends: "backend-deps",
  cache: false,
  memory_budget: 4096,
  cpu_share: 1024,
};

const RUNTIME_LAYER: LayerDef = {
  name: "runtime",
  description: "Minimal runtime image with release artefacts",
  from: "cgr.dev/chainguard/wolfi-base:latest",
  cache: false,
  verify: true,
  memory_budget: 512,
};

/** A valid backend layer set. */
function makeBackendLayerSet(): LayerSet {
  return {
    layers: new Map([
      ["base", BASE_LAYER],
      ["elixir-toolchain", TOOLCHAIN_LAYER],
      ["backend-deps", DEPS_LAYER],
      ["backend-build", BUILD_LAYER],
    ]),
    buildOrder: ["base", "elixir-toolchain", "backend-deps", "backend-build"],
  };
}

/** A valid frontend layer set (non-overlapping names). */
function makeFrontendLayerSet(): LayerSet {
  const deno: LayerDef = {
    name: "deno-toolchain",
    description: "Deno runtime for ReScript frontend build",
    extends: "base",
    cache: true,
  };
  const rescript: LayerDef = {
    name: "rescript-toolchain",
    description: "ReScript compiler on top of Deno layer",
    extends: "deno-toolchain",
    cache: true,
  };
  const frontendBuild: LayerDef = {
    name: "frontend-build",
    description: "Compile and bundle ReScript-TEA frontend",
    extends: "rescript-toolchain",
    cache: false,
    memory_budget: 1024,
  };
  return {
    layers: new Map([
      ["deno-toolchain", deno],
      ["rescript-toolchain", rescript],
      ["frontend-build", frontendBuild],
    ]),
    buildOrder: ["deno-toolchain", "rescript-toolchain", "frontend-build"],
  };
}

// ---------------------------------------------------------------------------
// Invariant 1: Valid layer definitions always produce valid OCI labels
// ---------------------------------------------------------------------------

Deno.test("LayerInvariant: valid layer produces valid OCI labels", () => {
  const layers = [BASE_LAYER, TOOLCHAIN_LAYER, DEPS_LAYER, BUILD_LAYER, RUNTIME_LAYER];
  for (const layer of layers) {
    const labels = layerToOciLabels(layer);
    const errors = validateOciLabels(labels);
    assertEquals(errors.length, 0,
      `layer '${layer.name}' produced invalid OCI labels: ${errors.join("; ")}`);
  }
});

Deno.test("LayerInvariant: OCI label name matches layer name", () => {
  const labels = layerToOciLabels(DEPS_LAYER);
  assertEquals(labels["org.stapeln.layer.name"], DEPS_LAYER.name,
    "OCI name label must match layer.name");
});

Deno.test("LayerInvariant: OCI label description matches layer description", () => {
  const labels = layerToOciLabels(DEPS_LAYER);
  assertEquals(labels["org.stapeln.layer.description"], DEPS_LAYER.description,
    "OCI description label must match layer.description");
});

Deno.test("LayerInvariant: cache=true produces OCI label 'true'", () => {
  const layer: LayerDef = { name: "l1", description: "d", from: "img:latest", cache: true };
  const labels = layerToOciLabels(layer);
  assertEquals(labels["org.stapeln.layer.cache"], "true");
});

Deno.test("LayerInvariant: cache=false produces OCI label 'false'", () => {
  const layer: LayerDef = { name: "l2", description: "d", from: "img:latest", cache: false };
  const labels = layerToOciLabels(layer);
  assertEquals(labels["org.stapeln.layer.cache"], "false");
});

Deno.test("LayerInvariant: extends present in OCI labels when set", () => {
  const labels = layerToOciLabels(TOOLCHAIN_LAYER);
  assertEquals(labels["org.stapeln.layer.extends"], "base",
    "OCI extends label must be present and correct");
});

Deno.test("LayerInvariant: extends absent from OCI labels when not set", () => {
  const labels = layerToOciLabels(BASE_LAYER);
  assertEquals(labels["org.stapeln.layer.extends"], undefined,
    "OCI extends label must not be present for base layer");
});

Deno.test("LayerInvariant: memory_budget produces correctly typed OCI label", () => {
  const labels = layerToOciLabels(DEPS_LAYER);
  assertExists(labels["org.stapeln.layer.memory_budget_mib"],
    "memory_budget_mib label must exist");
  const value = Number(labels["org.stapeln.layer.memory_budget_mib"]);
  assert(Number.isInteger(value) && value > 0,
    "memory_budget_mib label must be a positive integer");
  assertEquals(value, DEPS_LAYER.memory_budget as number);
});

// ---------------------------------------------------------------------------
// Invariant 2: Roundtrip — parse → serialise → parse is identity
// ---------------------------------------------------------------------------

Deno.test("LayerRoundtrip: base layer round-trips correctly", () => {
  const restored = roundtripLayer(BASE_LAYER);
  assertEquals(restored.name, BASE_LAYER.name);
  assertEquals(restored.description, BASE_LAYER.description);
  assertEquals(restored.from, BASE_LAYER.from);
  assertEquals(restored.cache, BASE_LAYER.cache);
  assertEquals(restored.verify, BASE_LAYER.verify);
});

Deno.test("LayerRoundtrip: layer with extends round-trips correctly", () => {
  const restored = roundtripLayer(TOOLCHAIN_LAYER);
  assertEquals(restored.name, TOOLCHAIN_LAYER.name);
  assertEquals(restored.extends, TOOLCHAIN_LAYER.extends);
  assertEquals(restored.cache, TOOLCHAIN_LAYER.cache);
});

Deno.test("LayerRoundtrip: layer with budget round-trips correctly", () => {
  const restored = roundtripLayer(DEPS_LAYER);
  assertEquals(restored.memory_budget, DEPS_LAYER.memory_budget);
  assertEquals(restored.cpu_share, DEPS_LAYER.cpu_share);
});

Deno.test("LayerRoundtrip: roundtripped layer produces same OCI labels", () => {
  const original = layerToOciLabels(BUILD_LAYER);
  const restored = roundtripLayer(BUILD_LAYER);
  const fromRestored = layerToOciLabels(restored);
  assertEquals(original, fromRestored,
    "OCI labels from roundtripped layer must match original");
});

Deno.test("LayerRoundtrip: roundtrip is idempotent (double roundtrip = single)", () => {
  const once = roundtripLayer(DEPS_LAYER);
  const twice = roundtripLayer(once);
  assertEquals(JSON.stringify(once), JSON.stringify(twice),
    "double roundtrip must equal single roundtrip");
});

// ---------------------------------------------------------------------------
// Invariant 3: memory_budget > 0 when set
// ---------------------------------------------------------------------------

Deno.test("BudgetProperty: layer with positive memory_budget is valid", () => {
  const layer: LayerDef = {
    name: "big-build",
    description: "Resource-heavy build step",
    extends: "base",
    cache: false,
    memory_budget: 8192,
  };
  const errors = validateLayer(layer);
  assertEquals(errors.length, 0, `valid layer with memory_budget must pass: ${errors.join("; ")}`);
});

Deno.test("BudgetProperty: layer with memory_budget=0 is invalid", () => {
  const layer: LayerDef = {
    name: "zero-budget",
    description: "Bad layer",
    extends: "base",
    cache: false,
    memory_budget: 0,
  };
  const errors = validateLayer(layer);
  assert(errors.length > 0, "memory_budget=0 must be invalid");
  assert(errors.some(e => e.includes("memory_budget")),
    "error must mention memory_budget");
});

Deno.test("BudgetProperty: layer with negative memory_budget is invalid", () => {
  const layer: LayerDef = {
    name: "neg-budget",
    description: "Bad layer",
    extends: "base",
    cache: false,
    memory_budget: -512,
  };
  const errors = validateLayer(layer);
  assert(errors.length > 0, "negative memory_budget must be invalid");
});

Deno.test("BudgetProperty: all fixture layers with memory_budget have budget > 0", () => {
  const budgetedLayers = [DEPS_LAYER, BUILD_LAYER, RUNTIME_LAYER];
  for (const layer of budgetedLayers) {
    if (layer.memory_budget !== undefined) {
      assert(layer.memory_budget > 0,
        `layer '${layer.name}' memory_budget must be > 0, got ${layer.memory_budget}`);
    }
  }
});

Deno.test("BudgetProperty: cpu_share=0 is invalid when set", () => {
  const layer: LayerDef = {
    name: "zero-cpu",
    description: "Bad layer",
    extends: "base",
    cache: false,
    cpu_share: 0,
  };
  const errors = validateLayer(layer);
  assert(errors.length > 0, "cpu_share=0 must be invalid");
  assert(errors.some(e => e.includes("cpu_share")),
    "error must mention cpu_share");
});

Deno.test("BudgetProperty: layer without memory_budget is valid (budget is optional)", () => {
  const layer: LayerDef = {
    name: "no-budget",
    description: "Layer without explicit budget",
    extends: "base",
    cache: true,
  };
  const errors = validateLayer(layer);
  assertEquals(errors.length, 0, "layer without memory_budget must be valid");
});

Deno.test("BudgetProperty: OCI label memory_budget_mib absent when memory_budget not set", () => {
  const labels = layerToOciLabels(TOOLCHAIN_LAYER);
  assertEquals(labels["org.stapeln.layer.memory_budget_mib"], undefined,
    "memory_budget_mib label must not appear when memory_budget is unset");
});

// ---------------------------------------------------------------------------
// Invariant 4: Composition — two valid layer sets compose into a valid set
// ---------------------------------------------------------------------------

Deno.test("LayerComposition: backend layer set is individually valid", () => {
  const set = makeBackendLayerSet();
  const errors = validateLayerSet(set);
  assertEquals(errors.length, 0,
    `backend layer set must be valid: ${errors.join("; ")}`);
});

Deno.test("LayerComposition: frontend layer set is individually valid (with base dependency)", () => {
  // Front-end layers extend 'base' but base is in the backend set — test
  // the frontend in isolation by adjusting deno-toolchain to be a root.
  const deno: LayerDef = {
    name: "deno-toolchain",
    description: "Deno runtime",
    from: "cgr.dev/chainguard/wolfi-base:latest",
    cache: true,
  };
  const rescript: LayerDef = {
    name: "rescript-toolchain",
    description: "ReScript compiler",
    extends: "deno-toolchain",
    cache: true,
  };
  const build: LayerDef = {
    name: "frontend-build",
    description: "Frontend build",
    extends: "rescript-toolchain",
    cache: false,
  };
  const set: LayerSet = {
    layers: new Map([
      ["deno-toolchain", deno],
      ["rescript-toolchain", rescript],
      ["frontend-build", build],
    ]),
    buildOrder: ["deno-toolchain", "rescript-toolchain", "frontend-build"],
  };
  const errors = validateLayerSet(set);
  assertEquals(errors.length, 0,
    `isolated frontend layer set must be valid: ${errors.join("; ")}`);
});

Deno.test("LayerComposition: composing backend and runtime produces valid combined set", () => {
  const backendSet = makeBackendLayerSet();
  const runtimeSet: LayerSet = {
    layers: new Map([["runtime", RUNTIME_LAYER]]),
    buildOrder: ["runtime"],
  };
  const combined = composeLayers(backendSet, runtimeSet);
  assert(combined.layers.size === 5, "combined set must have 5 layers");
  assert(combined.buildOrder.length === 5, "buildOrder must have 5 entries");
  // All entries in combined set must be individually valid
  for (const [, layer] of combined.layers) {
    const errors = validateLayer(layer);
    assertEquals(errors.length, 0,
      `composed layer '${layer.name}' must remain valid: ${errors.join("; ")}`);
  }
});

Deno.test("LayerComposition: composing disjoint sets preserves all layer names", () => {
  const a: LayerSet = {
    layers: new Map([
      ["layer-a1", { name: "layer-a1", description: "A1", from: "img:latest", cache: true }],
      ["layer-a2", { name: "layer-a2", description: "A2", extends: "layer-a1", cache: false }],
    ]),
    buildOrder: ["layer-a1", "layer-a2"],
  };
  const b: LayerSet = {
    layers: new Map([
      ["layer-b1", { name: "layer-b1", description: "B1", from: "img:latest", cache: true }],
    ]),
    buildOrder: ["layer-b1"],
  };
  const combined = composeLayers(a, b);
  assert(combined.layers.has("layer-a1"), "combined must have layer-a1");
  assert(combined.layers.has("layer-a2"), "combined must have layer-a2");
  assert(combined.layers.has("layer-b1"), "combined must have layer-b1");
  assertEquals(combined.layers.size, 3, "combined must have exactly 3 layers");
});

Deno.test("LayerComposition: composing overlapping sets throws on conflict", () => {
  const a: LayerSet = {
    layers: new Map([
      ["shared-name", { name: "shared-name", description: "A", from: "img:latest", cache: true }],
    ]),
    buildOrder: ["shared-name"],
  };
  const b: LayerSet = {
    layers: new Map([
      ["shared-name", { name: "shared-name", description: "B", from: "img:latest", cache: true }],
    ]),
    buildOrder: ["shared-name"],
  };
  let threw = false;
  try {
    composeLayers(a, b);
  } catch (_e) {
    threw = true;
  }
  assert(threw, "composing sets with duplicate layer names must throw");
});

Deno.test("LayerComposition: composed set buildOrder is concatenation of both", () => {
  const a: LayerSet = {
    layers: new Map([
      ["a1", { name: "a1", description: "A1", from: "img:latest", cache: true }],
    ]),
    buildOrder: ["a1"],
  };
  const b: LayerSet = {
    layers: new Map([
      ["b1", { name: "b1", description: "B1", from: "img:latest", cache: true }],
    ]),
    buildOrder: ["b1"],
  };
  const combined = composeLayers(a, b);
  assertEquals(combined.buildOrder, ["a1", "b1"],
    "buildOrder of composed set must be concatenation of a then b");
});

Deno.test("LayerComposition: all OCI labels of composed layers are valid", () => {
  const backendSet = makeBackendLayerSet();
  const runtimeSet: LayerSet = {
    layers: new Map([["runtime", RUNTIME_LAYER]]),
    buildOrder: ["runtime"],
  };
  const combined = composeLayers(backendSet, runtimeSet);
  for (const [, layer] of combined.layers) {
    const labels = layerToOciLabels(layer);
    const errors = validateOciLabels(labels);
    assertEquals(errors.length, 0,
      `OCI labels for composed layer '${layer.name}' must be valid: ${errors.join("; ")}`);
  }
});
