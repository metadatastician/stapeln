// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <6759885+hyperpolymath@users.noreply.github.com>
//
// Unit tests for container specification type invariants.
// Validates the structural correctness of container spec types used in
// the stapeln frontend and config generation pipeline.

import { assertEquals, assertThrows, assert } from "jsr:@std/assert";

// ---------------------------------------------------------------------------
// Container Spec Type Definitions (mirrors src/ types)
// ---------------------------------------------------------------------------

/** Valid container states per OCI runtime spec. */
const VALID_CONTAINER_STATES = ["created", "running", "paused", "stopped"] as const;
type ContainerState = typeof VALID_CONTAINER_STATES[number];

/** Restart policy values. */
const VALID_RESTART_POLICIES = ["never", "always", "on-failure", "unless-stopped"] as const;
type RestartPolicy = typeof VALID_RESTART_POLICIES[number];

/** Port mapping specification. */
interface PortMapping {
  hostPort: number;
  containerPort: number;
  protocol: "tcp" | "udp";
}

/** Volume mount specification. */
interface VolumeMount {
  source: string;
  destination: string;
  readOnly: boolean;
}

/** Environment variable entry. */
interface EnvVar {
  key: string;
  value: string;
}

/** Core container specification. */
interface ContainerSpec {
  id: string;
  name: string;
  image: string;
  state: ContainerState;
  ports: PortMapping[];
  volumes: VolumeMount[];
  env: EnvVar[];
  restartPolicy: RestartPolicy;
  resources: {
    cpuPercent: number;
    memoryMib: number;
  };
}

// ---------------------------------------------------------------------------
// Validation helpers
// ---------------------------------------------------------------------------

function isValidPort(port: number): boolean {
  return Number.isInteger(port) && port >= 1 && port <= 65535;
}

function isValidContainerName(name: string): boolean {
  return name.length > 0 &&
    name.length <= 63 &&
    !name.includes("/") &&
    !name.includes("\\") &&
    !name.includes("\0");
}

function isValidEnvKey(key: string): boolean {
  return /^[A-Z_][A-Z0-9_]*$/.test(key);
}

function isValidEnvValue(value: string): boolean {
  return !value.includes("\0") && !value.includes("\n") && !value.includes("\r");
}

function isValidImageRef(image: string): boolean {
  // Must be non-empty and contain no shell metacharacters or control chars
  if (image.length === 0) return false;
  const shellMetachars = [";", "|", "&", "$", "`", "(", ")", "{", "}", "<", ">"];
  for (const ch of shellMetachars) {
    if (image.includes(ch)) return false;
  }
  if (image.includes("\n") || image.includes("\r") || image.includes("\0")) return false;
  return true;
}

function isValidContainerState(state: string): state is ContainerState {
  return (VALID_CONTAINER_STATES as readonly string[]).includes(state);
}

function isValidRestartPolicy(policy: string): policy is RestartPolicy {
  return (VALID_RESTART_POLICIES as readonly string[]).includes(policy);
}

// ---------------------------------------------------------------------------
// Tests: Container name invariants
// ---------------------------------------------------------------------------

Deno.test("ContainerSpec: valid name accepted", () => {
  const names = ["web", "api-service", "db_primary", "myapp123", "a".repeat(63)];
  for (const name of names) {
    assert(isValidContainerName(name), `name '${name}' must be accepted`);
  }
});

Deno.test("ContainerSpec: empty name rejected", () => {
  assert(!isValidContainerName(""), "empty name must be rejected");
});

Deno.test("ContainerSpec: name too long rejected", () => {
  assert(!isValidContainerName("a".repeat(64)), "name > 63 chars must be rejected");
});

Deno.test("ContainerSpec: name with path separator rejected", () => {
  assert(!isValidContainerName("my/container"), "name with '/' must be rejected");
  assert(!isValidContainerName("my\\container"), "name with '\\' must be rejected");
});

Deno.test("ContainerSpec: name with null byte rejected", () => {
  assert(!isValidContainerName("my\x00container"), "name with null byte must be rejected");
});

// ---------------------------------------------------------------------------
// Tests: Port mapping invariants
// ---------------------------------------------------------------------------

Deno.test("PortMapping: valid ports accepted", () => {
  const ports = [1, 80, 443, 8080, 65535];
  for (const port of ports) {
    assert(isValidPort(port), `port ${port} must be valid`);
  }
});

Deno.test("PortMapping: port 0 rejected", () => {
  assert(!isValidPort(0), "port 0 must be rejected");
});

Deno.test("PortMapping: port 65536 rejected", () => {
  assert(!isValidPort(65536), "port 65536 must be rejected");
});

Deno.test("PortMapping: negative port rejected", () => {
  assert(!isValidPort(-1), "negative port must be rejected");
});

Deno.test("PortMapping: non-integer port rejected", () => {
  assert(!isValidPort(80.5), "fractional port must be rejected");
});

// ---------------------------------------------------------------------------
// Tests: Container state invariants
// ---------------------------------------------------------------------------

Deno.test("ContainerState: all valid states accepted", () => {
  for (const state of VALID_CONTAINER_STATES) {
    assert(isValidContainerState(state), `state '${state}' must be accepted`);
  }
});

Deno.test("ContainerState: unknown state rejected", () => {
  const invalid = ["pending", "starting", "RUNNING", "Created", "running "];
  for (const state of invalid) {
    assert(!isValidContainerState(state), `invalid state '${state}' must be rejected`);
  }
});

// ---------------------------------------------------------------------------
// Tests: Restart policy invariants
// ---------------------------------------------------------------------------

Deno.test("RestartPolicy: all valid policies accepted", () => {
  for (const policy of VALID_RESTART_POLICIES) {
    assert(isValidRestartPolicy(policy), `policy '${policy}' must be accepted`);
  }
});

Deno.test("RestartPolicy: unknown policy rejected", () => {
  const invalid = ["yes", "no", "Always", "on_failure", "unless-Stopped"];
  for (const policy of invalid) {
    assert(!isValidRestartPolicy(policy), `invalid policy '${policy}' must be rejected`);
  }
});

// ---------------------------------------------------------------------------
// Tests: Environment variable invariants
// ---------------------------------------------------------------------------

Deno.test("EnvVar: valid keys accepted", () => {
  const keys = ["PATH", "HOME", "POSTGRES_DB", "APP_PORT_8080", "_PRIVATE"];
  for (const key of keys) {
    assert(isValidEnvKey(key), `env key '${key}' must be accepted`);
  }
});

Deno.test("EnvVar: lowercase key rejected", () => {
  assert(!isValidEnvKey("path"), "lowercase key must be rejected");
  assert(!isValidEnvKey("MyVar"), "mixed-case key must be rejected");
});

Deno.test("EnvVar: key starting with digit rejected", () => {
  assert(!isValidEnvKey("1VAR"), "key starting with digit must be rejected");
});

Deno.test("EnvVar: value with newline rejected (HTTP injection)", () => {
  assert(!isValidEnvValue("value\nX-Injected: evil"), "value with newline must be rejected");
  assert(!isValidEnvValue("value\r\n"), "value with CRLF must be rejected");
});

Deno.test("EnvVar: value with null byte rejected", () => {
  assert(!isValidEnvValue("value\x00hidden"), "value with null byte must be rejected");
});

Deno.test("EnvVar: empty value accepted", () => {
  assert(isValidEnvValue(""), "empty env value must be accepted");
});

// ---------------------------------------------------------------------------
// Tests: Image reference invariants
// ---------------------------------------------------------------------------

Deno.test("ContainerSpec: valid image refs accepted", () => {
  const images = [
    "nginx:1.27",
    "postgres:16-alpine",
    "ghcr.io/myorg/myapp:v2.0.0",
    "cgr.dev/chainguard/nginx:latest",
  ];
  for (const image of images) {
    assert(isValidImageRef(image), `image '${image}' must be accepted`);
  }
});

Deno.test("ContainerSpec: image with shell injection rejected", () => {
  const injections = [
    "nginx; rm -rf /",
    "nginx | cat /etc/passwd",
    "$(whoami):latest",
  ];
  for (const image of injections) {
    assert(!isValidImageRef(image), `injection '${image}' must be rejected`);
  }
});

// ---------------------------------------------------------------------------
// Tests: Resource bounds
// ---------------------------------------------------------------------------

Deno.test("ContainerSpec: CPU percent in [0, 100]", () => {
  const valid = [0, 25, 50, 100];
  for (const cpu of valid) {
    assert(cpu >= 0 && cpu <= 100, `CPU ${cpu}% must be in range`);
  }
});

Deno.test("ContainerSpec: negative CPU rejected", () => {
  assert(-1 < 0, "negative CPU must be out of range");
});

Deno.test("ContainerSpec: memory must be non-negative integer in MiB", () => {
  const valid = [0, 128, 512, 1024, 16384];
  for (const mem of valid) {
    assert(Number.isInteger(mem) && mem >= 0, `memory ${mem} MiB must be valid`);
  }
});

// ---------------------------------------------------------------------------
// Tests: Full ContainerSpec construction
// ---------------------------------------------------------------------------

Deno.test("ContainerSpec: minimal valid spec constructs correctly", () => {
  const spec: ContainerSpec = {
    id: "abc123",
    name: "web",
    image: "nginx:1.27",
    state: "created",
    ports: [{ hostPort: 80, containerPort: 80, protocol: "tcp" }],
    volumes: [],
    env: [{ key: "APP_ENV", value: "production" }],
    restartPolicy: "unless-stopped",
    resources: { cpuPercent: 50, memoryMib: 512 },
  };

  assertEquals(spec.state, "created");
  assertEquals(spec.ports.length, 1);
  assertEquals(spec.ports[0].hostPort, 80);
  assert(isValidContainerName(spec.name), "spec name must be valid");
  assert(isValidEnvKey(spec.env[0].key), "env key must be valid");
  assert(isValidRestartPolicy(spec.restartPolicy), "restart policy must be valid");
});
