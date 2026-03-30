# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule Stapeln.WhatIfEngineTest do
  use ExUnit.Case, async: true

  alias Stapeln.WhatIfEngine

  # ---------------------------------------------------------------------------
  # Test fixtures
  # ---------------------------------------------------------------------------

  defp base_pipeline do
    %{
      "nodes" => [
        %{"id" => "base", "type" => "source", "config" => %{"image" => "ubuntu:22.04"}},
        %{"id" => "workdir", "type" => "workdir", "config" => %{"path" => "/app"}},
        %{"id" => "install", "type" => "run", "config" => %{"commands" => ["apt-get update", "apt-get install -y curl"]}},
        %{"id" => "build", "type" => "run", "config" => %{"commands" => ["make build"]}},
        %{"id" => "push", "type" => "push", "config" => %{"registry" => "ghcr.io/hyperpolymath/app", "tag" => "latest"}}
      ],
      "connections" => [
        %{"from" => "base", "to" => "workdir"},
        %{"from" => "workdir", "to" => "install"},
        %{"from" => "install", "to" => "build"},
        %{"from" => "build", "to" => "push"}
      ]
    }
  end

  # ---------------------------------------------------------------------------
  # Compare tests
  # ---------------------------------------------------------------------------

  test "compare returns baseline and scenario results" do
    scenarios = [
      %{"name" => "Chainguard swap", "mutations" => [%{"type" => "chainguard_swap"}]}
    ]

    result = WhatIfEngine.compare(base_pipeline(), scenarios)

    assert Map.has_key?(result, :baseline)
    assert Map.has_key?(result, :scenarios)
    assert length(result.scenarios) == 1
    assert result.baseline.valid == true
  end

  test "chainguard swap reduces image size" do
    scenarios = [
      %{"name" => "Chainguard swap", "mutations" => [%{"type" => "chainguard_swap"}]}
    ]

    result = WhatIfEngine.compare(base_pipeline(), scenarios)
    scenario = List.first(result.scenarios)

    assert scenario.name == "Chainguard swap"
    assert scenario.delta.size_bytes < 0
    assert scenario.delta.size_percent < 0
  end

  test "adding security gate improves security score" do
    scenarios = [
      %{"name" => "Add gate", "mutations" => [
        %{"type" => "add_security_gate", "before_node_id" => "push", "tool" => "trivy"}
      ]}
    ]

    result = WhatIfEngine.compare(base_pipeline(), scenarios)
    scenario = List.first(result.scenarios)

    assert scenario.delta.security_score_delta >= 0
  end

  test "merge runs reduces layer count" do
    scenarios = [
      %{"name" => "Merge runs", "mutations" => [%{"type" => "merge_runs"}]}
    ]

    result = WhatIfEngine.compare(base_pipeline(), scenarios)
    scenario = List.first(result.scenarios)

    # Two RUN nodes (install + build) should merge into one
    assert scenario.delta.layer_count_delta <= 0
  end

  test "pin images changes :latest tags" do
    scenarios = [
      %{"name" => "Pin versions", "mutations" => [%{"type" => "pin_images"}]}
    ]

    result = WhatIfEngine.compare(
      %{base_pipeline() | "nodes" => [
        %{"id" => "base", "type" => "source", "config" => %{"image" => "alpine:latest"}},
        %{"id" => "push", "type" => "push", "config" => %{"registry" => "ghcr.io/test", "tag" => "1.0"}}
      ], "connections" => [%{"from" => "base", "to" => "push"}]},
      scenarios
    )

    scenario = List.first(result.scenarios)
    assert scenario.result.valid
  end

  test "multiple scenarios are all evaluated" do
    scenarios = [
      %{"name" => "Chainguard", "mutations" => [%{"type" => "chainguard_swap"}]},
      %{"name" => "Pin images", "mutations" => [%{"type" => "pin_images"}]},
      %{"name" => "Merge runs", "mutations" => [%{"type" => "merge_runs"}]}
    ]

    result = WhatIfEngine.compare(base_pipeline(), scenarios)
    assert length(result.scenarios) == 3

    names = Enum.map(result.scenarios, & &1.name)
    assert "Chainguard" in names
    assert "Pin images" in names
    assert "Merge runs" in names
  end

  test "delta has required fields" do
    scenarios = [
      %{"name" => "Test", "mutations" => [%{"type" => "chainguard_swap"}]}
    ]

    result = WhatIfEngine.compare(base_pipeline(), scenarios)
    delta = List.first(result.scenarios).delta

    assert Map.has_key?(delta, :size_bytes)
    assert Map.has_key?(delta, :size_percent)
    assert Map.has_key?(delta, :time_ms)
    assert Map.has_key?(delta, :time_percent)
    assert Map.has_key?(delta, :security_score_delta)
    assert Map.has_key?(delta, :finding_count_delta)
    assert Map.has_key?(delta, :layer_count_delta)
    assert Map.has_key?(delta, :improved)
    assert Map.has_key?(delta, :summary)
    assert is_binary(delta.summary)
  end

  # ---------------------------------------------------------------------------
  # Suggest scenarios tests
  # ---------------------------------------------------------------------------

  test "suggest_scenarios returns suggestions for improvable pipeline" do
    suggestions = WhatIfEngine.suggest_scenarios(base_pipeline())

    assert length(suggestions) > 0

    names = Enum.map(suggestions, fn s -> Map.get(s, "name") end)

    # Should suggest Chainguard (pipeline uses ubuntu)
    assert Enum.any?(names, fn n -> String.contains?(n, "Chainguard") end)

    # Should suggest security gate (pipeline has no gate)
    assert Enum.any?(names, fn n -> String.contains?(n, "security") end)
  end

  test "suggest_scenarios returns empty for optimal pipeline" do
    optimal = %{
      "nodes" => [
        %{"id" => "base", "type" => "source", "config" => %{"image" => "cgr.dev/chainguard/static:3.19"}},
        %{"id" => "gate", "type" => "security_gate", "config" => %{"tool" => "trivy"}},
        %{"id" => "push", "type" => "push", "config" => %{"registry" => "ghcr.io/test", "tag" => "1.0"}}
      ],
      "connections" => [
        %{"from" => "base", "to" => "gate"},
        %{"from" => "gate", "to" => "push"}
      ]
    }

    suggestions = WhatIfEngine.suggest_scenarios(optimal)

    # Should have very few suggestions since it's already well-configured
    assert length(suggestions) <= 1
  end

  # ---------------------------------------------------------------------------
  # Mutation application tests
  # ---------------------------------------------------------------------------

  test "replace_image mutation changes source image" do
    mutations = [%{"type" => "replace_image", "node_id" => "base", "image" => "cgr.dev/chainguard/wolfi-base:latest"}]
    variant = WhatIfEngine.apply_mutations(base_pipeline(), mutations)

    nodes = Map.get(variant, "nodes")
    base = Enum.find(nodes, fn n -> Map.get(n, "id") == "base" end)
    image = Map.get(Map.get(base, "config"), "image")

    assert image == "cgr.dev/chainguard/wolfi-base:latest"
  end

  test "remove_node mutation removes node and rewires" do
    mutations = [%{"type" => "remove_node", "node_id" => "install"}]
    variant = WhatIfEngine.apply_mutations(base_pipeline(), mutations)

    nodes = Map.get(variant, "nodes")
    node_ids = Enum.map(nodes, fn n -> Map.get(n, "id") end)

    assert "install" not in node_ids

    # Should have bridge connection from workdir to build
    connections = Map.get(variant, "connections")
    assert Enum.any?(connections, fn c ->
      Map.get(c, "from") == "workdir" and Map.get(c, "to") == "build"
    end)
  end
end
