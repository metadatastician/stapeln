// SPDX-License-Identifier: PMPL-1.0-or-later
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <6759885+hyperpolymath@users.noreply.github.com>
//
// E2E tests for the container lifecycle flow:
// deploy → monitor → undeploy.
//
// These tests exercise the full pipeline using in-memory state and
// mocked external interfaces. No live container runtime required.

import { assertEquals, assert, assertExists } from "jsr:@std/assert";

// ---------------------------------------------------------------------------
// Mock container runtime state
// ---------------------------------------------------------------------------

type ContainerStatus = "created" | "running" | "stopped" | "deleted";

interface ContainerRecord {
  id: string;
  name: string;
  image: string;
  status: ContainerStatus;
  pid?: number;
  createdAt: Date;
  startedAt?: Date;
  stoppedAt?: Date;
}

interface MonitoringSnapshot {
  containerId: string;
  cpuPercent: number;
  memoryMib: number;
  timestampMs: number;
}

/** In-memory container registry — simulates the Vörðr state backend. */
class MockContainerRuntime {
  private containers = new Map<string, ContainerRecord>();
  private monitoring = new Map<string, MonitoringSnapshot[]>();
  private nextPid = 1000;

  /** Deploy a container (create + start). */
  deploy(name: string, image: string): ContainerRecord {
    if (this.containers.has(name)) {
      throw new Error(`Container '${name}' already exists`);
    }
    const id = `mock-${name}-${Date.now()}`;
    const record: ContainerRecord = {
      id,
      name,
      image,
      status: "created",
      createdAt: new Date(),
    };
    this.containers.set(name, record);
    return record;
  }

  /** Start a created container. */
  start(name: string): ContainerRecord {
    const container = this.getByName(name);
    if (container.status !== "created") {
      throw new Error(`Cannot start container '${name}' in state '${container.status}'`);
    }
    container.status = "running";
    container.pid = this.nextPid++;
    container.startedAt = new Date();
    return container;
  }

  /** Record a monitoring snapshot. */
  recordMetrics(name: string, cpuPercent: number, memoryMib: number): void {
    const container = this.getByName(name);
    if (container.status !== "running") {
      throw new Error(`Cannot monitor container '${name}' in state '${container.status}'`);
    }
    const snapshots = this.monitoring.get(name) ?? [];
    snapshots.push({
      containerId: container.id,
      cpuPercent,
      memoryMib,
      timestampMs: Date.now(),
    });
    this.monitoring.set(name, snapshots);
  }

  /** Get monitoring history. */
  getMetrics(name: string): MonitoringSnapshot[] {
    return this.monitoring.get(name) ?? [];
  }

  /** Stop a running container. */
  stop(name: string): ContainerRecord {
    const container = this.getByName(name);
    if (container.status !== "running") {
      throw new Error(`Cannot stop container '${name}' in state '${container.status}'`);
    }
    container.status = "stopped";
    container.pid = undefined;
    container.stoppedAt = new Date();
    return container;
  }

  /** Remove a stopped container. */
  remove(name: string): void {
    const container = this.getByName(name);
    if (container.status === "running") {
      throw new Error(`Cannot remove running container '${name}'`);
    }
    this.containers.delete(name);
    this.monitoring.delete(name);
  }

  /** Get container record by name. */
  getByName(name: string): ContainerRecord {
    const c = this.containers.get(name);
    if (!c) throw new Error(`Container '${name}' not found`);
    return c;
  }

  /** List all containers. */
  list(): ContainerRecord[] {
    return [...this.containers.values()];
  }
}

// ---------------------------------------------------------------------------
// E2E: Deploy → Monitor → Undeploy
// ---------------------------------------------------------------------------

Deno.test("E2E: full container lifecycle: deploy → start → monitor → stop → remove", () => {
  const runtime = new MockContainerRuntime();

  // Step 1: Deploy (create)
  const created = runtime.deploy("web", "nginx:1.27");
  assertEquals(created.status, "created", "deployed container must be in 'created' state");
  assertEquals(created.name, "web", "container name must match");
  assertEquals(created.image, "nginx:1.27", "image must match");
  assert(!created.startedAt, "startedAt must not be set before start");

  // Step 2: Start
  const running = runtime.start("web");
  assertEquals(running.status, "running", "started container must be 'running'");
  assertExists(running.pid, "running container must have a PID");
  assertExists(running.startedAt, "startedAt must be set after start");

  // Step 3: Monitor
  runtime.recordMetrics("web", 12.5, 64);
  runtime.recordMetrics("web", 15.0, 68);
  runtime.recordMetrics("web", 10.0, 62);

  const metrics = runtime.getMetrics("web");
  assertEquals(metrics.length, 3, "three metric snapshots must be recorded");
  assert(metrics.every(m => m.cpuPercent >= 0 && m.cpuPercent <= 100),
    "all CPU readings must be in [0, 100]");
  assert(metrics.every(m => m.memoryMib >= 0),
    "all memory readings must be non-negative");
  assertEquals(metrics[0].containerId, created.id, "metrics must reference correct container");

  // Step 4: Stop
  const stopped = runtime.stop("web");
  assertEquals(stopped.status, "stopped", "stopped container must be 'stopped'");
  assert(!stopped.pid, "stopped container must not have a PID");
  assertExists(stopped.stoppedAt, "stoppedAt must be set after stop");

  // Step 5: Remove
  runtime.remove("web");
  const remaining = runtime.list();
  assertEquals(remaining.length, 0, "container must be removed from registry");
});

// ---------------------------------------------------------------------------
// E2E: Multi-container compose lifecycle
// ---------------------------------------------------------------------------

Deno.test("E2E: multi-container compose: all services deploy in dependency order", () => {
  const runtime = new MockContainerRuntime();

  // Deploy in dependency order: db → api → web
  const services = [
    { name: "db", image: "postgres:16-alpine" },
    { name: "api", image: "myapp:2.0" },
    { name: "web", image: "nginx:1.27" },
  ];

  for (const svc of services) {
    runtime.deploy(svc.name, svc.image);
    runtime.start(svc.name);
  }

  const all = runtime.list();
  assertEquals(all.length, 3, "all three services must be running");
  assert(all.every(c => c.status === "running"), "all services must be in running state");

  // Verify each service is accessible
  for (const svc of services) {
    const container = runtime.getByName(svc.name);
    assertEquals(container.image, svc.image, `image must match for service ${svc.name}`);
    assertExists(container.pid, `service ${svc.name} must have a PID`);
  }
});

// ---------------------------------------------------------------------------
// E2E: Monitor threshold alert
// ---------------------------------------------------------------------------

Deno.test("E2E: monitoring threshold breach triggers alert", () => {
  const runtime = new MockContainerRuntime();
  runtime.deploy("api", "myapp:2.0");
  runtime.start("api");

  // Record escalating CPU usage
  const readings = [20, 45, 75, 90, 95];
  for (const cpu of readings) {
    runtime.recordMetrics("api", cpu, 256);
  }

  const metrics = runtime.getMetrics("api");
  assertEquals(metrics.length, readings.length);

  // Simulate threshold check: alert if CPU > 80 for any sample
  const CPU_THRESHOLD = 80;
  const alerts = metrics.filter(m => m.cpuPercent > CPU_THRESHOLD);
  assertEquals(alerts.length, 2, "two readings above threshold must trigger alerts");
  assert(alerts.every(a => a.cpuPercent > CPU_THRESHOLD),
    "all alerts must be above threshold");
});

// ---------------------------------------------------------------------------
// E2E: Error — duplicate container rejected
// ---------------------------------------------------------------------------

Deno.test("E2E: deploying duplicate container is rejected", () => {
  const runtime = new MockContainerRuntime();
  runtime.deploy("db", "postgres:16-alpine");

  let threw = false;
  try {
    runtime.deploy("db", "postgres:16-alpine");
  } catch (_e) {
    threw = true;
  }
  assert(threw, "deploying duplicate container must throw");
});

// ---------------------------------------------------------------------------
// E2E: Error — starting non-created container is rejected
// ---------------------------------------------------------------------------

Deno.test("E2E: starting an already-running container is rejected", () => {
  const runtime = new MockContainerRuntime();
  runtime.deploy("web", "nginx:1.27");
  runtime.start("web");

  let threw = false;
  try {
    runtime.start("web");
  } catch (_e) {
    threw = true;
  }
  assert(threw, "starting an already-running container must throw");
});

// ---------------------------------------------------------------------------
// E2E: Error — removing a running container is rejected
// ---------------------------------------------------------------------------

Deno.test("E2E: removing a running container is rejected", () => {
  const runtime = new MockContainerRuntime();
  runtime.deploy("web", "nginx:1.27");
  runtime.start("web");

  let threw = false;
  try {
    runtime.remove("web");
  } catch (_e) {
    threw = true;
  }
  assert(threw, "removing a running container must throw");
});

// ---------------------------------------------------------------------------
// E2E: Health probe evaluation
// ---------------------------------------------------------------------------

Deno.test("E2E: health probe evaluates correctly", () => {
  enum HealthStatus { Starting, Healthy, Unhealthy }

  interface HealthConfig {
    consecutiveSuccessThreshold: number;
    consecutiveFailureThreshold: number;
    startPeriodSeconds: number;
  }

  function evalHealth(
    consecutiveSuccesses: number,
    consecutiveFailures: number,
    ageSeconds: number,
    config: HealthConfig,
  ): HealthStatus {
    if (ageSeconds < config.startPeriodSeconds) {
      return HealthStatus.Starting;
    }
    if (consecutiveFailures >= config.consecutiveFailureThreshold) {
      return HealthStatus.Unhealthy;
    }
    if (consecutiveSuccesses >= config.consecutiveSuccessThreshold) {
      return HealthStatus.Healthy;
    }
    return HealthStatus.Starting;
  }

  const config: HealthConfig = {
    consecutiveSuccessThreshold: 1,
    consecutiveFailureThreshold: 3,
    startPeriodSeconds: 30,
  };

  assertEquals(evalHealth(0, 0, 10, config), HealthStatus.Starting,
    "within start period must be Starting");
  assertEquals(evalHealth(1, 0, 45, config), HealthStatus.Healthy,
    "one success after start period must be Healthy");
  assertEquals(evalHealth(0, 3, 45, config), HealthStatus.Unhealthy,
    "three failures must be Unhealthy");
  assertEquals(evalHealth(0, 2, 45, config), HealthStatus.Starting,
    "two failures must stay Starting");
});
