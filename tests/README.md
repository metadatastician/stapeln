# stapeln Test Suite

Comprehensive test coverage for validation, generation, and end-to-end workflows.

Two runtimes:

- **Idris2 (canonical, estate-aligned)** — `tests/idris2/` — 107 tests
  ported from the 5 Deno + 1 JS suites below; see
  `tests/idris2/README.adoc`. This is the single source of truth as
  of the 2026-05-20 estate port (8/11). Build:
  `idris2 --build stapeln-tests.ipkg && ./build/exec/stapeln-tests`.
- **Deno / Node (legacy, retained for cross-check)** — the TS/JS suites
  documented below remain runnable while the estate migration
  completes.

## Running Tests

### All Tests
```bash
cd tests
deno test --allow-read --allow-write stapeln.test.js
```

### Specific Test Categories
```bash
# Unit tests only (validation)
deno test --filter="Validation" stapeln.test.js

# Integration tests only (file generation)
deno test --filter="Generation" stapeln.test.js

# End-to-end tests
deno test --filter="E2E" stapeln.test.js
```

### With Coverage
```bash
deno test --coverage=cov_profile stapeln.test.js
deno coverage cov_profile
```

## Test Categories

### Unit Tests - Validation (9 tests)
- ✅ Unique Node IDs
- ✅ Port Numbers In Range
- ✅ Port Conflicts
- ✅ Valid Connections
- ✅ Resource Limits
- ✅ Firewall on Gateway Nodes
- ✅ Encrypted External Connections
- ✅ Acyclic Topology

### Integration Tests - File Generation (6 tests)
- ✅ Justfile Format
- ✅ Mustfile Format
- ✅ Trustfile.hs Format
- ✅ Dustfile Format
- ✅ stack.yaml Format
- ✅ Containerfile Format

### End-to-End Tests (2 tests)
- ✅ Complete Stack Generation
- ✅ Save and Load Design

## Test Data

Sample topology:
- 3 nodes (Gateway, Application, Database)
- 2 connections (encrypted)
- 4 validation rules

## CI Integration

Add to `.github/workflows/test.yml`:

```yaml
name: Test

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: denoland/setup-deno@v1
        with:
          deno-version: v1.x
      - name: Run tests
        run: deno test --allow-read --allow-write tests/stapeln.test.js
```

## Coverage Goals

- Unit tests: 100% of validation functions
- Integration tests: 100% of generation functions
- E2E tests: All major workflows

## Adding New Tests

1. Add test data to `sampleNodes` or `sampleConnections`
2. Write test using `Deno.test()`:
   ```javascript
   Deno.test("Category: Test Name", () => {
       // Test logic
       assert(condition, "Message");
   });
   ```
3. Run tests: `deno test stapeln.test.js`
