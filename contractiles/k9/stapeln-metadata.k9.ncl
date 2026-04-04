K9!
# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
# K9 Kennel-level guard: stapeln project metadata and container invariants
# Security Level: Kennel (data-only, no execution)
# No signature required

{
  pedigree = {
    schema_version = "1.0.0",
    component_type = "container-platform-metadata",
    security = {
      leash = 'Kennel,
      trust_level = "data-only",
      allow_network = false,
      allow_filesystem_write = false,
      allow_subprocess = false,
    },
    metadata = {
      name = "stapeln-metadata",
      version = "0.3.1",
      description = "Stapeln: supply-chain-verified container ecosystem — project invariants",
      author = "Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>",
    },
  },

  # Project configuration
  config = {
    # Container supply-chain invariants (CRITICAL)
    container = {
      # Must use Chainguard base images
      base_image_registry = "cgr.dev/chainguard",
      # Container files must be named "Containerfile" not "Dockerfile"
      containerfile_name = "Containerfile",
      # Must use Podman, not Docker
      runtime = "podman",
      # All images must be signed
      signing_required = true,
    },

    # Proof system invariants for crypto module
    proofs = {
      # Crypto module proofs in Idris2
      idris2_proofs_required = true,
      # No postulate for crypto correctness
      postulate_count_max = 6,
      # Note: 6 crypto postulates require stdlib improvements (unprovable today)
    },

    # Safety invariants
    safety = {
      forbidden_patterns = [
        "unwrap()",
        "expect()",
        "todo!()",
        "unimplemented!()",
      ],
    },

    # Test requirements
    tests = {
      min_unit_tests = 50,
      integration_tests_required = true,
      container_lifecycle_tests_required = true,
    },

    # Build/runtime
    build = {
      primary_language = "deno",
      zig_ffi = true,
      idris2_proofs = true,
    },

    # Language policy
    banned_files = ["Makefile", "Dockerfile"],
    banned_languages = ["python", "typescript", "go"],
  },

  # RSR compliance
  rsr = {
    explainme = true,
    ai_manifest = true,
    machine_readable = true,
    spdx_headers_required = true,
    security_md_required = true,
    idris2_abi = true,
    zig_ffi = true,
  },
}
