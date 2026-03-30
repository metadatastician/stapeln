# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Stapeln.WhatIfEngine - Compares pipeline variants for what-if analysis.
# "What if I switch from Ubuntu to Chainguard? What if I add a security gate?"

defmodule Stapeln.WhatIfEngine do
  @moduledoc """
  What-if analysis engine for container pipeline comparison.

  Given a baseline pipeline and one or more mutations (scenarios), this engine
  simulates each variant and produces a side-by-side comparison report. This
  lets users answer questions like:

  - "What if I switch from Ubuntu to Chainguard?"
  - "What if I add a security scan before push?"
  - "What if I use multi-stage builds?"
  - "What if I merge my RUN commands?"

  ## Scenarios

  A scenario is a named set of mutations to apply to the baseline pipeline:

      %{
        "name" => "Switch to Chainguard",
        "mutations" => [
          %{"type" => "replace_image", "node_id" => "base", "image" => "cgr.dev/chainguard/wolfi-base:latest"},
        ]
      }

  ## Supported mutation types

  | Type              | Fields                          | Effect                           |
  |-------------------|---------------------------------|----------------------------------|
  | `replace_image`   | node_id, image                  | Change base image of a source    |
  | `add_node`        | node, after_node_id             | Insert a new node after another  |
  | `remove_node`     | node_id                         | Remove a node and rewire edges   |
  | `merge_runs`      | (none)                          | Merge consecutive RUN nodes      |
  | `add_security_gate` | before_node_id, tool           | Insert security gate before node |
  | `pin_images`      | (none)                          | Pin all :latest tags to digest   |
  | `chainguard_swap` | (none)                          | Replace all images with Chainguard equivalents |
  """

  alias Stapeln.BuildSimulator
  alias Stapeln.PipelineEngine

  # ---------------------------------------------------------------------------
  # Types
  # ---------------------------------------------------------------------------

  @type mutation :: %{String.t() => term()}

  @type scenario :: %{
          name: String.t(),
          mutations: [mutation()]
        }

  @type comparison :: %{
          baseline: map(),
          scenarios: [%{name: String.t(), result: map(), delta: map()}]
        }

  # ---------------------------------------------------------------------------
  # Chainguard image equivalents for common base images
  # ---------------------------------------------------------------------------

  @chainguard_equivalents %{
    "alpine" => "cgr.dev/chainguard/wolfi-base",
    "ubuntu" => "cgr.dev/chainguard/wolfi-base",
    "debian" => "cgr.dev/chainguard/wolfi-base",
    "fedora" => "cgr.dev/chainguard/wolfi-base",
    "centos" => "cgr.dev/chainguard/wolfi-base",
    "node" => "cgr.dev/chainguard/node",
    "python" => "cgr.dev/chainguard/python",
    "golang" => "cgr.dev/chainguard/go",
    "rust" => "cgr.dev/chainguard/rust",
    "nginx" => "cgr.dev/chainguard/nginx",
    "postgres" => "cgr.dev/chainguard/postgres",
    "redis" => "cgr.dev/chainguard/redis"
  }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Run what-if analysis comparing a baseline pipeline against one or more scenarios.

  Each scenario describes a set of mutations to apply. Returns the baseline
  simulation result plus each scenario result with a computed delta showing
  improvements or regressions.

  ## Example

      WhatIfEngine.compare(pipeline, [
        %{"name" => "Chainguard swap", "mutations" => [%{"type" => "chainguard_swap"}]},
        %{"name" => "Add security gate", "mutations" => [%{"type" => "add_security_gate", "before_node_id" => "push", "tool" => "trivy"}]}
      ])
  """
  @spec compare(map(), [map()]) :: comparison()
  def compare(pipeline, scenarios) when is_map(pipeline) and is_list(scenarios) do
    baseline = BuildSimulator.simulate(pipeline)

    scenario_results =
      Enum.map(scenarios, fn scenario ->
        name = Map.get(scenario, "name", Map.get(scenario, :name, "unnamed"))
        mutations = Map.get(scenario, "mutations", Map.get(scenario, :mutations, []))

        # Apply all mutations to produce the variant pipeline
        variant = apply_mutations(pipeline, mutations)

        # Simulate the variant
        result = BuildSimulator.simulate(variant)

        # Compute the delta (improvement or regression)
        delta = compute_delta(baseline, result)

        %{name: name, result: result, delta: delta, variant_pipeline: variant}
      end)

    %{
      baseline: baseline,
      scenarios: scenario_results
    }
  end

  def compare(_, _), do: %{baseline: %{valid: false, errors: ["pipeline must be a map"]}, scenarios: []}

  @doc """
  Generate a set of recommended scenarios based on pipeline analysis.

  Inspects the pipeline for common improvement opportunities and returns
  ready-to-use scenario definitions the user can select from.
  """
  @spec suggest_scenarios(map()) :: [map()]
  def suggest_scenarios(pipeline) when is_map(pipeline) do
    nodes = get_nodes(pipeline)
    suggestions = []

    # Suggest Chainguard swap if any non-Chainguard images
    has_non_chainguard =
      Enum.any?(nodes, fn n ->
        node_type(n) == "source" and
          not String.contains?(to_string(config_value(node_config(n), "image")), "cgr.dev/chainguard")
      end)

    suggestions =
      if has_non_chainguard do
        [%{
          "name" => "Switch to Chainguard images",
          "description" => "Replace base images with Chainguard equivalents for smaller size and better security",
          "mutations" => [%{"type" => "chainguard_swap"}],
          "expected_impact" => "size_reduction, security_improvement"
        } | suggestions]
      else
        suggestions
      end

    # Suggest security gate if missing
    has_gate = Enum.any?(nodes, fn n -> node_type(n) == "security_gate" end)
    push_nodes = Enum.filter(nodes, fn n -> node_type(n) == "push" end)

    suggestions =
      if not has_gate and length(push_nodes) > 0 do
        push_id = node_id(List.first(push_nodes))

        [%{
          "name" => "Add security scanning",
          "description" => "Insert a Trivy security gate before push to catch vulnerabilities",
          "mutations" => [%{"type" => "add_security_gate", "before_node_id" => push_id, "tool" => "trivy"}],
          "expected_impact" => "security_improvement, time_increase"
        } | suggestions]
      else
        suggestions
      end

    # Suggest RUN merge if many consecutive RUN nodes
    run_count = Enum.count(nodes, fn n -> node_type(n) == "run" end)

    suggestions =
      if run_count > 3 do
        [%{
          "name" => "Merge RUN commands",
          "description" => "Combine #{run_count} RUN commands into fewer layers for smaller image",
          "mutations" => [%{"type" => "merge_runs"}],
          "expected_impact" => "size_reduction"
        } | suggestions]
      else
        suggestions
      end

    # Suggest image pinning if :latest tags
    has_latest =
      Enum.any?(nodes, fn n ->
        node_type(n) == "source" and
          String.ends_with?(to_string(config_value(node_config(n), "image")), ":latest")
      end)

    suggestions =
      if has_latest do
        [%{
          "name" => "Pin image versions",
          "description" => "Replace :latest tags with specific version tags for reproducible builds",
          "mutations" => [%{"type" => "pin_images"}],
          "expected_impact" => "reproducibility"
        } | suggestions]
      else
        suggestions
      end

    Enum.reverse(suggestions)
  end

  def suggest_scenarios(_), do: []

  # ---------------------------------------------------------------------------
  # Mutation application
  # ---------------------------------------------------------------------------

  @doc false
  def apply_mutations(pipeline, mutations) when is_list(mutations) do
    Enum.reduce(mutations, pipeline, &apply_mutation/2)
  end

  defp apply_mutation(%{"type" => "replace_image"} = mut, pipeline) do
    target_id = Map.get(mut, "node_id")
    new_image = Map.get(mut, "image")

    update_node(pipeline, target_id, fn node ->
      config = node_config(node)
      updated_config = Map.put(config, "image", new_image)
      node |> Map.put("config", updated_config) |> Map.put(:config, updated_config)
    end)
  end

  defp apply_mutation(%{"type" => "add_security_gate"} = mut, pipeline) do
    before_id = Map.get(mut, "before_node_id")
    tool = Map.get(mut, "tool", "trivy")
    gate_id = "sim-gate-#{:erlang.phash2({before_id, tool})}"

    gate_node = %{
      "id" => gate_id,
      "type" => "security_gate",
      "config" => %{"tool" => tool, "severity" => "HIGH,CRITICAL"}
    }

    insert_node_before(pipeline, before_id, gate_node)
  end

  defp apply_mutation(%{"type" => "remove_node"} = mut, pipeline) do
    target_id = Map.get(mut, "node_id")
    remove_node(pipeline, target_id)
  end

  defp apply_mutation(%{"type" => "merge_runs"}, pipeline) do
    PipelineEngine.optimize(pipeline)
  end

  defp apply_mutation(%{"type" => "pin_images"}, pipeline) do
    nodes = get_nodes(pipeline)

    updated_nodes =
      Enum.map(nodes, fn node ->
        if node_type(node) == "source" do
          config = node_config(node)
          image = config_value(config, "image") || ""
          image_str = to_string(image)

          pinned =
            if String.ends_with?(image_str, ":latest") do
              # Replace :latest with a simulated pinned version
              base = String.replace_suffix(image_str, ":latest", "")
              "#{base}:3.19-r0"
            else
              if not String.contains?(image_str, ":") do
                "#{image_str}:stable"
              else
                image_str
              end
            end

          updated_config = Map.put(config, "image", pinned)
          node |> Map.put("config", updated_config) |> Map.put(:config, updated_config)
        else
          node
        end
      end)

    put_nodes(pipeline, updated_nodes)
  end

  defp apply_mutation(%{"type" => "chainguard_swap"}, pipeline) do
    nodes = get_nodes(pipeline)

    updated_nodes =
      Enum.map(nodes, fn node ->
        if node_type(node) == "source" do
          config = node_config(node)
          image = to_string(config_value(config, "image") || "")

          # Extract the base image name without tag
          image_base = image |> String.split(":") |> List.first() |> to_string()

          # Check if there's a Chainguard equivalent
          equivalent =
            Enum.find_value(@chainguard_equivalents, fn {pattern, replacement} ->
              if String.contains?(image_base, pattern) and
                   not String.contains?(image_base, "cgr.dev"),
                 do: replacement,
                 else: nil
            end)

          if equivalent do
            # Preserve the tag if it existed, otherwise use :latest
            tag =
              case String.split(image, ":") do
                [_, t] -> t
                _ -> "latest"
              end

            new_image = "#{equivalent}:#{tag}"
            updated_config = Map.put(config, "image", new_image)
            node |> Map.put("config", updated_config) |> Map.put(:config, updated_config)
          else
            node
          end
        else
          node
        end
      end)

    put_nodes(pipeline, updated_nodes)
  end

  defp apply_mutation(%{"type" => "add_node"} = mut, pipeline) do
    node = Map.get(mut, "node")
    after_id = Map.get(mut, "after_node_id")

    if node && after_id do
      insert_node_after(pipeline, after_id, node)
    else
      pipeline
    end
  end

  defp apply_mutation(_, pipeline), do: pipeline

  # ---------------------------------------------------------------------------
  # Delta computation
  # ---------------------------------------------------------------------------

  defp compute_delta(baseline, variant) do
    size_delta = variant.total_size - baseline.total_size
    time_delta = variant.total_time_ms - baseline.total_time_ms
    score_delta = variant.security_score - baseline.security_score
    finding_delta = length(variant.security_findings) - length(baseline.security_findings)
    layer_delta = length(variant.layers) - length(baseline.layers)

    size_pct =
      if baseline.total_size > 0,
        do: Float.round(size_delta / baseline.total_size * 100, 1),
        else: 0.0

    time_pct =
      if baseline.total_time_ms > 0,
        do: Float.round(time_delta / baseline.total_time_ms * 100, 1),
        else: 0.0

    %{
      size_bytes: size_delta,
      size_percent: size_pct,
      time_ms: time_delta,
      time_percent: time_pct,
      security_score_delta: Float.round(score_delta, 1),
      finding_count_delta: finding_delta,
      layer_count_delta: layer_delta,
      cache_hit_ratio_delta: Float.round(variant.cache_hit_ratio - baseline.cache_hit_ratio, 2),
      improved: size_delta <= 0 and score_delta >= 0,
      summary: build_summary(size_delta, time_delta, score_delta)
    }
  end

  defp build_summary(size_delta, time_delta, score_delta) do
    parts = []

    parts =
      cond do
        size_delta < -1_000_000 ->
          mb = Float.round(abs(size_delta) / 1_000_000, 1)
          ["#{mb}MB smaller" | parts]

        size_delta > 1_000_000 ->
          mb = Float.round(size_delta / 1_000_000, 1)
          ["#{mb}MB larger" | parts]

        true ->
          parts
      end

    parts =
      cond do
        time_delta < -1_000 ->
          secs = Float.round(abs(time_delta) / 1000, 1)
          ["#{secs}s faster" | parts]

        time_delta > 1_000 ->
          secs = Float.round(time_delta / 1000, 1)
          ["#{secs}s slower" | parts]

        true ->
          parts
      end

    parts =
      cond do
        score_delta > 5.0 -> ["+#{score_delta} security" | parts]
        score_delta < -5.0 -> ["#{score_delta} security" | parts]
        true -> parts
      end

    case parts do
      [] -> "no significant change"
      _ -> Enum.reverse(parts) |> Enum.join(", ")
    end
  end

  # ---------------------------------------------------------------------------
  # Pipeline graph manipulation helpers
  # ---------------------------------------------------------------------------

  defp insert_node_before(pipeline, before_id, new_node) do
    new_id = Map.get(new_node, "id", "")
    nodes = get_nodes(pipeline)
    connections = get_connections(pipeline)

    # Find all connections that target before_id and redirect them to new_node
    {redirected, kept} =
      Enum.split_with(connections, fn c ->
        conn_to(c) == before_id
      end)

    new_incoming =
      Enum.map(redirected, fn c ->
        Map.put(c, "to", new_id) |> Map.put(:to, new_id)
      end)

    # Add connection from new_node to the original target
    bridge = %{"from" => new_id, "to" => before_id}

    updated_connections = kept ++ new_incoming ++ [bridge]

    pipeline
    |> put_nodes(nodes ++ [new_node])
    |> put_connections(updated_connections)
  end

  defp insert_node_after(pipeline, after_id, new_node) do
    new_id = Map.get(new_node, "id", "")
    nodes = get_nodes(pipeline)
    connections = get_connections(pipeline)

    # Find all connections from after_id and redirect them from new_node
    {redirected, kept} =
      Enum.split_with(connections, fn c ->
        conn_from(c) == after_id
      end)

    new_outgoing =
      Enum.map(redirected, fn c ->
        Map.put(c, "from", new_id) |> Map.put(:from, new_id)
      end)

    # Add connection from after_id to new_node
    bridge = %{"from" => after_id, "to" => new_id}

    updated_connections = kept ++ new_outgoing ++ [bridge]

    pipeline
    |> put_nodes(nodes ++ [new_node])
    |> put_connections(updated_connections)
  end

  defp remove_node(pipeline, target_id) do
    nodes = get_nodes(pipeline)
    connections = get_connections(pipeline)

    # Find incoming and outgoing connections for the removed node
    incoming = Enum.filter(connections, fn c -> conn_to(c) == target_id end)
    outgoing = Enum.filter(connections, fn c -> conn_from(c) == target_id end)

    # Create bridge connections (every incoming source -> every outgoing target)
    bridges =
      for inc <- incoming, out <- outgoing do
        %{"from" => conn_from(inc), "to" => conn_to(out)}
      end

    # Remove the node and its connections
    remaining_nodes = Enum.reject(nodes, fn n -> node_id(n) == target_id end)

    remaining_connections =
      connections
      |> Enum.reject(fn c -> conn_from(c) == target_id or conn_to(c) == target_id end)

    pipeline
    |> put_nodes(remaining_nodes)
    |> put_connections(remaining_connections ++ bridges)
  end

  defp update_node(pipeline, target_id, update_fn) do
    nodes = get_nodes(pipeline)

    updated =
      Enum.map(nodes, fn node ->
        if node_id(node) == target_id, do: update_fn.(node), else: node
      end)

    put_nodes(pipeline, updated)
  end

  # ---------------------------------------------------------------------------
  # Node accessors (same pattern as BuildSimulator)
  # ---------------------------------------------------------------------------

  defp get_nodes(pipeline) do
    case Map.get(pipeline, "nodes", Map.get(pipeline, :nodes, [])) do
      list when is_list(list) -> list
      _ -> []
    end
  end

  defp get_connections(pipeline) do
    case Map.get(pipeline, "connections", Map.get(pipeline, :connections, [])) do
      list when is_list(list) -> list
      _ -> []
    end
  end

  defp node_id(node), do: Map.get(node, "id", Map.get(node, :id, ""))
  defp node_type(node), do: Map.get(node, "type", Map.get(node, :type, ""))
  defp node_config(node), do: Map.get(node, "config", Map.get(node, :config, %{}))
  defp conn_from(c), do: Map.get(c, "from", Map.get(c, :from, ""))
  defp conn_to(c), do: Map.get(c, "to", Map.get(c, :to, ""))

  defp config_value(config, key) when is_map(config) do
    Map.get(config, key, Map.get(config, String.to_atom(key), nil))
  end

  defp config_value(_, _), do: nil

  defp put_nodes(pipeline, nodes) do
    cond do
      Map.has_key?(pipeline, "nodes") -> Map.put(pipeline, "nodes", nodes)
      Map.has_key?(pipeline, :nodes) -> Map.put(pipeline, :nodes, nodes)
      true -> Map.put(pipeline, "nodes", nodes)
    end
  end

  defp put_connections(pipeline, connections) do
    cond do
      Map.has_key?(pipeline, "connections") -> Map.put(pipeline, "connections", connections)
      Map.has_key?(pipeline, :connections) -> Map.put(pipeline, :connections, connections)
      true -> Map.put(pipeline, "connections", connections)
    end
  end
end
