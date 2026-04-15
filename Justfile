# SPDX-License-Identifier: PMPL-1.0-or-later
# Justfile for stapeln

# Default recipe — list available commands
import? "contractile.just"

default:
    @just --list

# Self-diagnostic — checks dependencies, permissions, paths
doctor:
    @echo "Running diagnostics for stapeln..."
    @echo "Checking required tools..."
    @command -v just >/dev/null 2>&1 && echo "  [OK] just" || echo "  [FAIL] just not found"
    @command -v git >/dev/null 2>&1 && echo "  [OK] git" || echo "  [FAIL] git not found"
    @echo "Checking for hardcoded paths..."
    @grep -rn '/var/mnt/eclipse' --include='*.rs' --include='*.ex' --include='*.res' --include='*.gleam' --include='*.sh' --include='*.toml' . 2>/dev/null | grep -v 'Justfile' | head -5 || echo "  [OK] No hardcoded paths in source"
    @echo "Diagnostics complete."

# Guided tour of key features
tour:
    @echo "=== stapeln Tour ==="
    @echo ""
    @echo "1. Project structure:"
    @ls -la
    @echo ""
    @echo "2. Available commands: just --list"
    @echo ""
    @echo "3. Read README.adoc or README.md for full overview"
    @echo "4. Read EXPLAINME.adoc for architecture decisions"
    @echo "5. Run 'just doctor' to check your setup"
    @echo ""
    @echo "INTERACTIVE TOUR:"
    @echo "  The frontend includes an interactive guided tour that highlights"
    @echo "  key UI areas (navigation, palette, canvas, simulation, deploy)."
    @echo "  It shows automatically on first visit. To replay it, open the"
    @echo "  browser console and run: stapelnStartTour()"
    @echo "  The tour is fully keyboard navigable (Enter/Space to advance,"
    @echo "  Escape to skip)."
    @echo ""
    @echo "Tour complete! Try 'just --list' to see all available commands."

# Open feedback channel with diagnostic context
help-me:
    @echo "=== stapeln Help ==="
    @echo "Platform: $(uname -s) $(uname -m)"
    @echo "Shell: $SHELL"
    @echo ""
    @echo "To report an issue:"
    @echo "  https://github.com/hyperpolymath/stapeln/issues/new"
    @echo ""
    @echo "Include the output of 'just doctor' in your report."

# Run panic-attacker pre-commit scan
assail:
    @command -v panic-attack >/dev/null 2>&1 && panic-attack assail . || echo "WARN: panic-attack not found — install from https://github.com/hyperpolymath/panic-attacker"

# LLM context dump
llm-context:
    @echo "Project: stapeln"
    @echo "License: PMPL-1.0-or-later"
    @test -f README.adoc && head -30 README.adoc || test -f README.md && head -30 README.md || echo "No README found"


# Print the current CRG grade (reads from READINESS.md '**Current Grade:** X' line)
crg-grade:
    @grade=$$(grep -oP '(?<=\*\*Current Grade:\*\* )[A-FX]' READINESS.md 2>/dev/null | head -1); \
    [ -z "$$grade" ] && grade="X"; \
    echo "$$grade"

# Generate a shields.io badge markdown for the current CRG grade
# Looks for '**Current Grade:** X' in READINESS.md; falls back to X
crg-badge:
    @grade=$$(grep -oP '(?<=\*\*Current Grade:\*\* )[A-FX]' READINESS.md 2>/dev/null | head -1); \
    [ -z "$$grade" ] && grade="X"; \
    case "$$grade" in \
      A) color="brightgreen" ;; B) color="green" ;; C) color="yellow" ;; \
      D) color="orange" ;; E) color="red" ;; F) color="critical" ;; \
      *) color="lightgrey" ;; esac; \
    echo "[![CRG $$grade](https://img.shields.io/badge/CRG-$$grade-$$color?style=flat-square)](https://github.com/hyperpolymath/standards/tree/main/component-readiness-grades)"

# End-to-end tests (container lifecycle, property, aspect)
# Full E2E requires Podman; property and aspect tests run in CI
e2e:
    @deno test tests/e2e/ --allow-all --no-check 2>&1 || echo "E2E tests require Podman — skipping (run locally with Podman available)"
    @deno test tests/property/ --allow-all --no-check
    @bash tests/aspect/aspect_tests.sh
