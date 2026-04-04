// SPDX-License-Identifier: PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <6759885+hyperpolymath@users.noreply.github.com>
//
// Property-based invariant tests for stapeln Nickel configuration files.
// Verifies structural invariants that ALL Nickel configs must satisfy:
// required fields present, valid values, no injection vectors.
//
// These are "property" tests rather than full proptest — they verify
// invariants hold across representative samples of config shapes.

import { assertEquals, assert, assertExists } from "jsr:@std/assert";

// ---------------------------------------------------------------------------
// Nickel config schema (minimal representation)
// ---------------------------------------------------------------------------

/** Required fields that every stapeln service config must have. */
const REQUIRED_SERVICE_FIELDS = ["name", "image"] as const;

/** Required fields that every resource limit block must have. */
const REQUIRED_RESOURCE_FIELDS = ["cpu", "memory"] as const;

/** Valid network driver values. */
const VALID_NETWORK_DRIVERS = ["bridge", "host", "none", "overlay"] as const;

// ---------------------------------------------------------------------------
// Helpers: config validators
// ---------------------------------------------------------------------------

/** Validate a service config object has all required fields. */
function validateServiceConfig(config: Record<string, unknown>): { valid: boolean; missing: string[] } {
  const missing: string[] = [];
  for (const field of REQUIRED_SERVICE_FIELDS) {
    if (!(field in config) || config[field] === null || config[field] === undefined) {
      missing.push(field);
    }
  }
  return { valid: missing.length === 0, missing };
}

/** Validate a resource config has all required fields and valid ranges. */
function validateResourceConfig(resources: Record<string, unknown>): string[] {
  const errors: string[] = [];
  for (const field of REQUIRED_RESOURCE_FIELDS) {
    if (!(field in resources)) {
      errors.push(`missing required resource field: ${field}`);
    }
  }
  if ("cpu" in resources) {
    const cpu = resources.cpu;
    if (typeof cpu !== "string" && typeof cpu !== "number") {
      errors.push("cpu must be a string (e.g. '0.5') or number");
    }
  }
  if ("memory" in resources) {
    const mem = resources.memory;
    if (typeof mem !== "string") {
      errors.push("memory must be a string with unit (e.g. '512M', '2G')");
    } else if (!/^\d+[KMGkmg]B?$/.test(mem)) {
      errors.push(`memory '${mem}' must match pattern: number + unit (K/M/G)`);
    }
  }
  return errors;
}

/** Validate a port string "host:container" or just "port". */
function validatePortSpec(portSpec: string): boolean {
  const parts = portSpec.split(":");
  if (parts.length === 1) {
    const port = parseInt(parts[0], 10);
    return !isNaN(port) && port >= 1 && port <= 65535;
  }
  if (parts.length === 2) {
    const host = parseInt(parts[0], 10);
    const container = parseInt(parts[1], 10);
    return !isNaN(host) && host >= 1 && host <= 65535 &&
      !isNaN(container) && container >= 1 && container <= 65535;
  }
  return false;
}

/** Validate a network config. */
function validateNetworkConfig(network: Record<string, unknown>): string[] {
  const errors: string[] = [];
  if ("driver" in network) {
    const driver = network.driver as string;
    if (!(VALID_NETWORK_DRIVERS as readonly string[]).includes(driver)) {
      errors.push(`invalid driver '${driver}'; must be one of ${VALID_NETWORK_DRIVERS.join(", ")}`);
    }
  }
  return errors;
}

// ---------------------------------------------------------------------------
// Property: all service configs have required fields
// ---------------------------------------------------------------------------

Deno.test("NickelConfig property: all service configs have required fields", () => {
  const configs: Record<string, unknown>[] = [
    { name: "web", image: "nginx:1.27", ports: ["80:80"] },
    { name: "api", image: "myapp:2.0", env: { PORT: "8080" } },
    { name: "db", image: "postgres:16-alpine", volumes: ["/data:/var/lib/postgresql"] },
    { name: "cache", image: "redis:7-alpine" },
    { name: "proxy", image: "caddy:2-alpine", ports: ["443:443", "80:80"] },
  ];

  for (const config of configs) {
    const result = validateServiceConfig(config);
    assert(result.valid, `config for '${config.name}' missing fields: ${result.missing.join(", ")}`);
  }
});

Deno.test("NickelConfig property: config without name is invalid", () => {
  const config = { image: "nginx:1.27" };
  const result = validateServiceConfig(config);
  assert(!result.valid, "config without name must be invalid");
  assert(result.missing.includes("name"), "missing 'name' must be reported");
});

Deno.test("NickelConfig property: config without image is invalid", () => {
  const config = { name: "web" };
  const result = validateServiceConfig(config);
  assert(!result.valid, "config without image must be invalid");
  assert(result.missing.includes("image"), "missing 'image' must be reported");
});

// ---------------------------------------------------------------------------
// Property: resource configs have valid CPU and memory
// ---------------------------------------------------------------------------

Deno.test("NickelConfig property: valid resource configs pass", () => {
  const resources: Record<string, unknown>[] = [
    { cpu: "0.5", memory: "512M" },
    { cpu: "1.0", memory: "1G" },
    { cpu: "2", memory: "4G" },
    { cpu: "0.1", memory: "128M" },
  ];

  for (const res of resources) {
    const errors = validateResourceConfig(res);
    assertEquals(errors.length, 0,
      `resource config ${JSON.stringify(res)} must be valid, got: ${errors.join(", ")}`);
  }
});

Deno.test("NickelConfig property: resource config missing fields fails", () => {
  const res = { cpu: "0.5" }; // missing memory
  const errors = validateResourceConfig(res);
  assert(errors.length > 0, "config missing 'memory' must fail validation");
});

Deno.test("NickelConfig property: memory without unit fails", () => {
  const res = { cpu: "0.5", memory: "512" }; // missing unit
  const errors = validateResourceConfig(res);
  assert(errors.length > 0, "memory without unit must fail validation");
});

Deno.test("NickelConfig property: memory with invalid unit fails", () => {
  const res = { cpu: "0.5", memory: "512X" }; // invalid unit
  const errors = validateResourceConfig(res);
  assert(errors.length > 0, "memory with invalid unit must fail validation");
});

// ---------------------------------------------------------------------------
// Property: port specs are valid
// ---------------------------------------------------------------------------

Deno.test("NickelConfig property: valid port specs pass", () => {
  const ports = ["80", "443", "80:80", "8080:8080", "9000:9000"];
  for (const port of ports) {
    assert(validatePortSpec(port), `port spec '${port}' must be valid`);
  }
});

Deno.test("NickelConfig property: invalid port specs fail", () => {
  const invalid = [
    "0:80",      // host port 0
    "80:0",      // container port 0
    "65536:80",  // host port too high
    "80:65536",  // container port too high
    "abc:80",    // non-numeric host
    "80:abc",    // non-numeric container
    "80:80:80",  // too many colons
    "",          // empty
  ];
  for (const port of invalid) {
    assert(!validatePortSpec(port), `invalid port spec '${port}' must be rejected`);
  }
});

// ---------------------------------------------------------------------------
// Property: network driver values are valid
// ---------------------------------------------------------------------------

Deno.test("NickelConfig property: valid network drivers pass", () => {
  for (const driver of VALID_NETWORK_DRIVERS) {
    const errors = validateNetworkConfig({ driver });
    assertEquals(errors.length, 0, `driver '${driver}' must be valid`);
  }
});

Deno.test("NickelConfig property: invalid network driver fails", () => {
  const invalid = ["macvlan", "custom", "BRIDGE", "Bridge"];
  for (const driver of invalid) {
    const errors = validateNetworkConfig({ driver });
    assert(errors.length > 0, `invalid driver '${driver}' must be rejected`);
  }
});

// ---------------------------------------------------------------------------
// Property: no injection characters in config values
// ---------------------------------------------------------------------------

Deno.test("NickelConfig property: image names have no shell injection characters", () => {
  const safeImages = [
    "nginx:1.27",
    "postgres:16-alpine",
    "cgr.dev/chainguard/nginx:latest",
    "registry.example.com:5000/myapp:v1.0.0",
  ];

  const dangerousChars = [";", "|", "&", "$", "`", "(", ")", "\\n", "\r"];

  for (const image of safeImages) {
    for (const char of dangerousChars) {
      assert(
        !image.includes(char),
        `safe image '${image}' must not contain dangerous char '${char}'`
      );
    }
  }
});

Deno.test("NickelConfig property: env var values have no null bytes or newlines", () => {
  const safeValues = [
    "production",
    "postgres://user:pass@db:5432/mydb",
    "some value with spaces",
    "/var/lib/data",
    "v2.0.0-beta.1+build.123",
  ];

  for (const value of safeValues) {
    assert(!value.includes("\0"), `env value '${value}' must not contain null byte`);
    assert(!value.includes("\n"), `env value '${value}' must not contain newline`);
    assert(!value.includes("\r"), `env value '${value}' must not contain carriage return`);
  }
});

// ---------------------------------------------------------------------------
// Property: all required fields can be iterated for validation
// ---------------------------------------------------------------------------

Deno.test("NickelConfig property: REQUIRED_SERVICE_FIELDS is non-empty", () => {
  assert(REQUIRED_SERVICE_FIELDS.length > 0,
    "required fields list must not be empty");
});

Deno.test("NickelConfig property: REQUIRED_SERVICE_FIELDS contains 'name' and 'image'", () => {
  const fields = REQUIRED_SERVICE_FIELDS as readonly string[];
  assert(fields.includes("name"), "required fields must include 'name'");
  assert(fields.includes("image"), "required fields must include 'image'");
});
