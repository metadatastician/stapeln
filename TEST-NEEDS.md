# TEST-NEEDS: stapeln

## Current State

| Category | Count | Details |
|----------|-------|---------|
| **Source modules** | 94+ | Rust across container-stack (selur, vordr, cerro-torre), verified-container-spec, 44 Nickel configs, 4 Idris2 ABI |
| **Unit tests (inline Rust)** | 186 | Spread across selur compose commands, vordr, cerro-torre |
| **Unit tests (JS)** | ~79 | stapeln.test.js (73 assertions), test_assert.js (6) |
| **Integration tests** | 0 | No dedicated integration test files |
| **E2E tests** | 0 | None |
| **Benchmarks** | 3 files | selur ipc_benchmark.rs, vordr container_lifecycle.rs, vordr ebpf_overhead.rs |
| **Fuzz tests** | 2 | selur compose fuzz + selur fuzz targets |

## What's Missing

### P2P Tests (CRITICAL)
- [ ] No tests for selur <-> vordr communication
- [ ] No tests for cerro-torre integration with selur
- [ ] No cross-component container lifecycle tests

### E2E Tests (CRITICAL)
- [ ] No test that runs a full container build-deploy-monitor cycle
- [ ] No test for the verified-container-spec shim with actual containerd
- [ ] No test for Nickel config evaluation with actual container deployment

### Aspect Tests
- [ ] **Security**: Container security tool with no security-focused tests (namespace escape, capability leakage, eBPF bypass)
- [ ] **Performance**: Benchmark files exist but need verification they actually run
- [ ] **Concurrency**: No tests for concurrent container operations, race conditions in lifecycle management
- [ ] **Error handling**: No tests for OCI spec violations, malformed container images, network partitions

### Build & Execution
- [ ] No Nickel config validation tests (44 configs, 0 tests)
- [ ] No Idris2 ABI compilation test
- [ ] No verified-container-spec proof verification

### Benchmarks Status
- [x] ipc_benchmark.rs exists (selur)
- [x] container_lifecycle.rs exists (vordr)
- [x] ebpf_overhead.rs exists (vordr)
- [ ] No benchmark for Nickel config evaluation
- [ ] No benchmark for container image pull/push

### Self-Tests
- [ ] No container runtime self-diagnostic
- [ ] No health probe for vordr monitoring

## FLAGGED ISSUES
- **186 inline tests for 94 source files** = decent unit test count but NO integration or E2E
- **Container security platform with 0 security-specific tests** -- critical gap
- **44 Nickel configs with 0 validation tests** -- config correctness unverified
- **verified-container-spec has no proof verification tests** -- "verified" is a claim, not a fact

## Priority: P1 (HIGH)

## FAKE-FUZZ ALERT

- `tests/fuzz/placeholder.txt` is a scorecard placeholder inherited from rsr-template-repo — it does NOT provide real fuzz testing
- Replace with an actual fuzz harness (see rsr-template-repo/tests/fuzz/README.adoc) or remove the file
- Priority: P2 — creates false impression of fuzz coverage
