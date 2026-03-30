# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule Stapeln.BuildSimulatorTest do
  use ExUnit.Case, async: true

  alias Stapeln.BuildSimulator

  # ---------------------------------------------------------------------------
  # Test fixtures
  # ---------------------------------------------------------------------------

  defp simple_pipeline do
    %{
      "nodes" => [
        %{"id" => "base", "type" => "source", "config" => %{"image" => "cgr.dev/chainguard/wolfi-base:latest"}},
        %{"id" => "workdir", "type" => "workdir", "config" => %{"path" => "/app"}},
        %{"id" => "deps", "type" => "copy", "config" => %{"src" => "package.json", "dst" => "."}},
        %{"id" => "install", "type" => "run", "config" => %{"commands" => ["apk add nodejs", "npm ci"]}},
        %{"id" => "src", "type" => "copy", "config" => %{"src" => ".", "dst" => "."}},
        %{"id" => "port", "type" => "expose", "config" => %{"port" => 3000}},
        %{"id" => "gate", "type" => "security_gate", "config" => %{"tool" => "trivy"}},
        %{"id" => "push", "type" => "push", "config" => %{"registry" => "ghcr.io/hyperpolymath/app", "tag" => "1.0.0"}}
      ],
      "connections" => [
        %{"from" => "base", "to" => "workdir"},
        %{"from" => "workdir", "to" => "deps"},
        %{"from" => "deps", "to" => "install"},
        %{"from" => "install", "to" => "src"},
        %{"from" => "src", "to" => "port"},
        %{"from" => "port", "to" => "gate"},
        %{"from" => "gate", "to" => "push"}
      ]
    }
  end

  defp insecure_pipeline do
    %{
      "nodes" => [
        %{"id" => "base", "type" => "source", "config" => %{"image" => "ubuntu"}},
        %{"id" => "env", "type" => "env", "config" => %{"key" => "API_KEY", "value" => "sk-secret123"}},
        %{"id" => "run", "type" => "run", "config" => %{"commands" => ["curl https://example.com/script.sh | bash", "chmod 777 /app"]}},
        %{"id" => "push", "type" => "push", "config" => %{"registry" => "docker.io/myapp", "tag" => "latest"}}
      ],
      "connections" => [
        %{"from" => "base", "to" => "env"},
        %{"from" => "env", "to" => "run"},
        %{"from" => "run", "to" => "push"}
      ]
    }
  end

  defp chainguard_pipeline do
    %{
      "nodes" => [
        %{"id" => "base", "type" => "source", "config" => %{"image" => "cgr.dev/chainguard/static:latest"}},
        %{"id" => "copy", "type" => "copy", "config" => %{"src" => "binary", "dst" => "/app/binary"}},
        %{"id" => "gate", "type" => "security_gate", "config" => %{"tool" => "trivy"}},
        %{"id" => "push", "type" => "push", "config" => %{"registry" => "ghcr.io/hyperpolymath/static-app", "tag" => "1.0.0"}}
      ],
      "connections" => [
        %{"from" => "base", "to" => "copy"},
        %{"from" => "copy", "to" => "gate"},
        %{"from" => "gate", "to" => "push"}
      ]
    }
  end

  # ---------------------------------------------------------------------------
  # Basic simulation tests
  # ---------------------------------------------------------------------------

  test "simulate returns valid result for simple pipeline" do
    result = BuildSimulator.simulate(simple_pipeline())

    assert result.valid == true
    assert length(result.layers) == 8
    assert result.total_size > 0
    assert result.total_time_ms > 0
    assert is_float(result.security_score)
    assert is_float(result.cache_hit_ratio)
    assert is_binary(result.containerfile_preview)
    assert result.errors == []
  end

  test "simulate returns invalid for empty pipeline" do
    result = BuildSimulator.simulate(%{"nodes" => [], "connections" => []})

    assert result.valid == false
    assert length(result.errors) > 0
  end

  test "simulate returns invalid for non-map" do
    result = BuildSimulator.simulate("not a map")

    assert result.valid == false
  end

  # ---------------------------------------------------------------------------
  # Layer analysis tests
  # ---------------------------------------------------------------------------

  test "layers have required fields" do
    result = BuildSimulator.simulate(simple_pipeline())

    for layer <- result.layers do
      assert Map.has_key?(layer, :node_id)
      assert Map.has_key?(layer, :node_type)
      assert Map.has_key?(layer, :instruction)
      assert Map.has_key?(layer, :estimated_size)
      assert Map.has_key?(layer, :estimated_time_ms)
      assert Map.has_key?(layer, :cacheable)
      assert Map.has_key?(layer, :cache_key)
      assert Map.has_key?(layer, :security_notes)
      assert Map.has_key?(layer, :layer_index)
      assert is_binary(layer.instruction)
      assert is_integer(layer.estimated_size)
      assert is_integer(layer.estimated_time_ms)
      assert is_boolean(layer.cacheable)
    end
  end

  test "source layer uses base image size lookup" do
    result = BuildSimulator.simulate(simple_pipeline())
    base_layer = Enum.find(result.layers, fn l -> l.node_id == "base" end)

    assert base_layer != nil
    assert String.starts_with?(base_layer.instruction, "FROM")
    assert base_layer.estimated_size > 0
  end

  test "RUN layer estimates package installation size" do
    result = BuildSimulator.simulate(simple_pipeline())
    run_layer = Enum.find(result.layers, fn l -> l.node_id == "install" end)

    assert run_layer != nil
    assert String.starts_with?(run_layer.instruction, "RUN")
    assert run_layer.estimated_size > 0
    assert run_layer.estimated_time_ms > 0
  end

  test "Chainguard images are smaller than distro images" do
    cg_result = BuildSimulator.simulate(chainguard_pipeline())
    insecure_result = BuildSimulator.simulate(insecure_pipeline())

    cg_base = Enum.find(cg_result.layers, fn l -> l.node_type == "source" end)
    insecure_base = Enum.find(insecure_result.layers, fn l -> l.node_type == "source" end)

    assert cg_base.estimated_size < insecure_base.estimated_size
  end

  # ---------------------------------------------------------------------------
  # Security analysis tests
  # ---------------------------------------------------------------------------

  test "insecure pipeline produces security findings" do
    result = BuildSimulator.simulate(insecure_pipeline())

    assert length(result.security_findings) > 0

    # Should find the secret in ENV
    assert Enum.any?(result.security_findings, fn f ->
      f.severity == "critical" and String.contains?(f.message, "API_KEY")
    end)

    # Should find missing security gate
    assert Enum.any?(result.security_findings, fn f ->
      f.severity == "high" and String.contains?(f.message, "security gate")
    end)
  end

  test "Chainguard pipeline has higher security score" do
    cg_result = BuildSimulator.simulate(chainguard_pipeline())
    insecure_result = BuildSimulator.simulate(insecure_pipeline())

    assert cg_result.security_score > insecure_result.security_score
  end

  test "security notes detect curl in RUN commands" do
    result = BuildSimulator.simulate(insecure_pipeline())
    run_layer = Enum.find(result.layers, fn l -> l.node_type == "run" end)

    assert Enum.any?(run_layer.security_notes, fn note ->
      String.contains?(note, "curl") or String.contains?(note, "download")
    end)
  end

  # ---------------------------------------------------------------------------
  # Timeline tests
  # ---------------------------------------------------------------------------

  test "timeline has stages in order" do
    result = BuildSimulator.simulate(simple_pipeline())

    assert length(result.timeline) > 0

    stages = Enum.map(result.timeline, & &1.stage)
    assert stages == Enum.sort(stages)
  end

  test "timeline entries have required fields" do
    result = BuildSimulator.simulate(simple_pipeline())

    for entry <- result.timeline do
      assert Map.has_key?(entry, :stage)
      assert Map.has_key?(entry, :node_ids)
      assert Map.has_key?(entry, :parallel)
      assert Map.has_key?(entry, :estimated_time_ms)
      assert is_integer(entry.stage)
      assert is_list(entry.node_ids)
      assert is_boolean(entry.parallel)
    end
  end

  # ---------------------------------------------------------------------------
  # Supply chain tests
  # ---------------------------------------------------------------------------

  test "supply chain extracts source images" do
    result = BuildSimulator.simulate(simple_pipeline())

    assert length(result.supply_chain) > 0

    for sc <- result.supply_chain do
      assert Map.has_key?(sc, :image)
      assert Map.has_key?(sc, :registry)
      assert Map.has_key?(sc, :trust_level)
      assert Map.has_key?(sc, :signed)
      assert Map.has_key?(sc, :sbom_available)
      assert Map.has_key?(sc, :chainguard)
    end
  end

  test "Chainguard images are identified as trusted" do
    result = BuildSimulator.simulate(chainguard_pipeline())

    for sc <- result.supply_chain do
      assert sc.chainguard == true
      assert sc.trust_level == :high
    end
  end

  # ---------------------------------------------------------------------------
  # Optimisation hints tests
  # ---------------------------------------------------------------------------

  test "hints suggest Chainguard for non-Chainguard images" do
    result = BuildSimulator.simulate(insecure_pipeline())

    assert Enum.any?(result.optimisation_hints, fn hint ->
      String.contains?(hint, "Chainguard")
    end)
  end

  # ---------------------------------------------------------------------------
  # Containerfile preview tests
  # ---------------------------------------------------------------------------

  test "containerfile preview is generated" do
    result = BuildSimulator.simulate(simple_pipeline())

    assert String.length(result.containerfile_preview) > 0
    assert String.contains?(result.containerfile_preview, "FROM")
    assert String.contains?(result.containerfile_preview, "WORKDIR")
  end
end
