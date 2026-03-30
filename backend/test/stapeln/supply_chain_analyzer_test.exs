# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule Stapeln.SupplyChainAnalyzerTest do
  use ExUnit.Case, async: true

  alias Stapeln.SupplyChainAnalyzer

  # ---------------------------------------------------------------------------
  # Test fixtures
  # ---------------------------------------------------------------------------

  defp chainguard_pipeline do
    %{
      "nodes" => [
        %{"id" => "base", "type" => "source", "config" => %{"image" => "cgr.dev/chainguard/wolfi-base:3.19"}},
        %{"id" => "copy", "type" => "copy", "config" => %{"src" => "app/", "dst" => "/app/"}},
        %{"id" => "gate", "type" => "security_gate", "config" => %{"tool" => "trivy"}},
        %{"id" => "push", "type" => "push", "config" => %{"registry" => "ghcr.io/hyperpolymath/app", "tag" => "1.0.0"}}
      ],
      "connections" => [
        %{"from" => "base", "to" => "copy"},
        %{"from" => "copy", "to" => "gate"},
        %{"from" => "gate", "to" => "push"}
      ]
    }
  end

  defp insecure_pipeline do
    %{
      "nodes" => [
        %{"id" => "base", "type" => "source", "config" => %{"image" => "ubuntu"}},
        %{"id" => "fetch", "type" => "run", "config" => %{"commands" => ["curl https://example.com/install.sh | bash"]}},
        %{"id" => "push", "type" => "push", "config" => %{"registry" => "docker.io/myapp", "tag" => "latest"}}
      ],
      "connections" => [
        %{"from" => "base", "to" => "fetch"},
        %{"from" => "fetch", "to" => "push"}
      ]
    }
  end

  defp pinned_pipeline do
    %{
      "nodes" => [
        %{"id" => "base", "type" => "source", "config" => %{"image" => "cgr.dev/chainguard/static@sha256:abc123def456"}},
        %{"id" => "copy", "type" => "copy", "config" => %{"src" => "binary", "dst" => "/app/binary"}},
        %{"id" => "gate", "type" => "security_gate", "config" => %{"tool" => "trivy"}},
        %{"id" => "push", "type" => "push", "config" => %{"registry" => "ghcr.io/hyperpolymath/app", "tag" => "1.0.0"}}
      ],
      "connections" => [
        %{"from" => "base", "to" => "copy"},
        %{"from" => "copy", "to" => "gate"},
        %{"from" => "gate", "to" => "push"}
      ]
    }
  end

  # ---------------------------------------------------------------------------
  # SLSA level tests
  # ---------------------------------------------------------------------------

  test "pinned Chainguard image achieves SLSA level 3" do
    result = SupplyChainAnalyzer.analyze(pinned_pipeline())

    assert result.slsa_level == 3
  end

  test "tagged Chainguard image achieves SLSA level 2" do
    result = SupplyChainAnalyzer.analyze(chainguard_pipeline())

    assert result.slsa_level >= 2
  end

  test "untagged Docker Hub image is SLSA level 0" do
    result = SupplyChainAnalyzer.analyze(insecure_pipeline())

    assert result.slsa_level == 0
  end

  # ---------------------------------------------------------------------------
  # Risk score tests
  # ---------------------------------------------------------------------------

  test "secure pipeline has low risk score" do
    result = SupplyChainAnalyzer.analyze(pinned_pipeline())

    assert result.risk_score < 30.0
  end

  test "insecure pipeline has high risk score" do
    result = SupplyChainAnalyzer.analyze(insecure_pipeline())

    assert result.risk_score > 30.0
  end

  # ---------------------------------------------------------------------------
  # Image provenance tests
  # ---------------------------------------------------------------------------

  test "image provenance includes all source images" do
    result = SupplyChainAnalyzer.analyze(chainguard_pipeline())

    assert length(result.image_provenance) == 1

    prov = List.first(result.image_provenance)
    assert prov.chainguard == true
    assert prov.registry == "cgr.dev"
    assert prov.signed == true
    assert prov.sbom == true
  end

  test "Docker Hub images are identified as low trust" do
    result = SupplyChainAnalyzer.analyze(insecure_pipeline())

    prov = List.first(result.image_provenance)
    assert prov.trust_level == :low
    assert prov.chainguard == false
  end

  # ---------------------------------------------------------------------------
  # Trust boundary tests
  # ---------------------------------------------------------------------------

  test "trust boundaries are detected" do
    result = SupplyChainAnalyzer.analyze(insecure_pipeline())

    assert length(result.trust_boundaries) > 0

    # Should detect high-risk boundary before push (no security gate)
    assert Enum.any?(result.trust_boundaries, fn b ->
      b.risk == :high and b.boundary_type == :build_to_registry
    end)
  end

  test "security gate lowers push trust boundary risk" do
    result = SupplyChainAnalyzer.analyze(chainguard_pipeline())

    push_boundaries = Enum.filter(result.trust_boundaries, fn b ->
      b.boundary_type == :build_to_registry
    end)

    assert Enum.all?(push_boundaries, fn b -> b.risk == :low end)
  end

  # ---------------------------------------------------------------------------
  # Reproducibility tests
  # ---------------------------------------------------------------------------

  test "pipeline with curl is not reproducible" do
    result = SupplyChainAnalyzer.analyze(insecure_pipeline())
    assert result.reproducible == false
  end

  test "pipeline without network fetches and pinned images is reproducible" do
    result = SupplyChainAnalyzer.analyze(pinned_pipeline())
    assert result.reproducible == true
  end

  # ---------------------------------------------------------------------------
  # Findings tests
  # ---------------------------------------------------------------------------

  test "findings include unsigned images" do
    result = SupplyChainAnalyzer.analyze(insecure_pipeline())

    assert Enum.any?(result.findings, fn f ->
      f.category == "signing"
    end)
  end

  test "findings include unpinned images" do
    result = SupplyChainAnalyzer.analyze(insecure_pipeline())

    assert Enum.any?(result.findings, fn f ->
      f.category == "pinning"
    end)
  end

  test "findings include network fetch warnings" do
    result = SupplyChainAnalyzer.analyze(insecure_pipeline())

    assert Enum.any?(result.findings, fn f ->
      f.category == "network_fetch"
    end)
  end

  # ---------------------------------------------------------------------------
  # Recommendations tests
  # ---------------------------------------------------------------------------

  test "recommendations suggest Chainguard for non-Chainguard images" do
    result = SupplyChainAnalyzer.analyze(insecure_pipeline())

    assert Enum.any?(result.recommendations, fn r ->
      String.contains?(r, "Chainguard")
    end)
  end

  test "recommendations suggest pinning for unpinned images" do
    result = SupplyChainAnalyzer.analyze(insecure_pipeline())

    assert Enum.any?(result.recommendations, fn r ->
      String.contains?(r, "pin") or String.contains?(r, "Pin")
    end)
  end

  # ---------------------------------------------------------------------------
  # Edge cases
  # ---------------------------------------------------------------------------

  test "analyze handles non-map input" do
    result = SupplyChainAnalyzer.analyze("not a map")
    assert result.slsa_level == 0
    assert result.risk_score == 100.0
  end

  test "analyze handles empty pipeline" do
    result = SupplyChainAnalyzer.analyze(%{"nodes" => [], "connections" => []})
    assert result.slsa_level == 0
    assert result.image_provenance == []
  end

  test "dependency depth is computed correctly" do
    result = SupplyChainAnalyzer.analyze(chainguard_pipeline())
    assert result.dependency_depth >= 1
  end
end
