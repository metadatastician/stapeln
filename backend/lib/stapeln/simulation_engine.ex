# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule Stapeln.SimulationEngine do
  @moduledoc """
  Simulation dry-run engine for Stapeln assembly pipelines.

  Accepts a pipeline graph and simulates packet flow through it:
  - Validates topology (DAG, connectivity, port conflicts)
  - Traces packet paths from source to terminal nodes
  - Applies network conditions (latency, drop rate, jitter)
  - Checks firewall/security gate rules
  - Generates a deterministic event log

  Returns a dry-run result with success/failure semantics suitable
  for the frontend SimulationMode.res packet animation.

  Determinism: uses a seed-based PRNG for reproducible simulations.
  Scope (MVP): network path simulation only — no container start time
  or health checks.
  """

  alias Stapeln.PipelineEngine

  # ---------------------------------------------------------------------------
  # Types
  # ---------------------------------------------------------------------------

  @type packet :: %{
          id: String.t(),
          type: atom(),
          source: String.t(),
          target: String.t(),
          status: atom(),
          timestamp: float(),
          size: non_neg_integer(),
          encrypted: boolean()
        }

  @type event :: %{
          type: atom(),
          packet_id: String.t(),
          timestamp: float(),
          metadata: map()
        }

  @type dry_run_result :: %{
          valid: boolean(),
          events: [event()],
          packets_sent: non_neg_integer(),
          packets_delivered: non_neg_integer(),
          packets_dropped: non_neg_integer(),
          avg_latency_ms: float(),
          throughput: float(),
          blockers: [String.t()],
          security_findings: [map()],
          validation: map()
        }

  @type sim_params :: %{
          packet_rate: float(),
          latency_ms: float(),
          drop_rate: float(),
          jitter_ms: float(),
          seed: non_neg_integer(),
          duration_steps: non_neg_integer()
        }

  @default_params %{
    packet_rate: 4.0,
    latency_ms: 50.0,
    drop_rate: 0.02,
    jitter_ms: 10.0,
    seed: 42,
    duration_steps: 100
  }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Run a dry-run simulation on a pipeline.

  First validates the pipeline, then if valid, simulates packet flow through
  the graph. Returns a dry_run_result with events and summary metrics.

  Options:
  - params: simulation parameters (packet_rate, latency_ms, drop_rate, jitter_ms, seed, duration_steps)
  """
  @spec dry_run(map(), map()) :: dry_run_result()
  def dry_run(pipeline, params \\ %{}) when is_map(pipeline) do
    sim_params = Map.merge(@default_params, params)

    # Phase 1: validate topology
    validation = PipelineEngine.validate(pipeline)

    unless validation.valid do
      %{
        valid: false,
        events: [],
        packets_sent: 0,
        packets_delivered: 0,
        packets_dropped: 0,
        avg_latency_ms: 0.0,
        throughput: 0.0,
        blockers: validation.errors,
        security_findings: [],
        validation: validation
      }
    else
      # Phase 2: build graph structures
      nodes = get_nodes(pipeline)
      connections = get_connections(pipeline)
      node_index = index_nodes(nodes)
      adjacency = build_adjacency(connections)
      security_gates = find_security_gates(nodes)

      # Phase 3: find source and terminal nodes
      sources = find_sources(nodes)
      terminals = find_terminals(nodes)

      # Phase 4: compute paths from each source to each terminal
      paths = compute_all_paths(sources, terminals, adjacency, node_index)

      if paths == [] do
        %{
          valid: false,
          events: [],
          packets_sent: 0,
          packets_delivered: 0,
          packets_dropped: 0,
          avg_latency_ms: 0.0,
          throughput: 0.0,
          blockers: ["no valid paths from source to terminal nodes"],
          security_findings: [],
          validation: validation
        }
      else
        # Phase 5: simulate packet flow
        {events, metrics} =
          simulate_packets(paths, security_gates, node_index, sim_params)

        # Phase 6: compute security findings
        security_findings = detect_security_issues(events, security_gates, nodes)

        %{
          valid: metrics.dropped == 0 and security_findings == [],
          events: events,
          packets_sent: metrics.sent,
          packets_delivered: metrics.delivered,
          packets_dropped: metrics.dropped,
          avg_latency_ms: metrics.avg_latency,
          throughput: metrics.throughput,
          blockers: [],
          security_findings: security_findings,
          validation: validation
        }
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Graph operations
  # ---------------------------------------------------------------------------

  defp get_nodes(pipeline) do
    Map.get(pipeline, "nodes", Map.get(pipeline, :nodes, []))
  end

  defp get_connections(pipeline) do
    Map.get(pipeline, "connections", Map.get(pipeline, :connections, []))
  end

  defp index_nodes(nodes) do
    Map.new(nodes, fn node ->
      id = Map.get(node, "id", Map.get(node, :id, ""))
      {id, node}
    end)
  end

  defp build_adjacency(connections) do
    Enum.reduce(connections, %{}, fn conn, acc ->
      from = Map.get(conn, "from", Map.get(conn, :from, ""))
      to = Map.get(conn, "to", Map.get(conn, :to, ""))

      Map.update(acc, from, [to], fn existing -> [to | existing] end)
    end)
  end

  defp find_sources(nodes) do
    Enum.filter(nodes, fn node ->
      type = Map.get(node, "type", Map.get(node, :type, ""))
      type in ["source", "FROM"]
    end)
    |> Enum.map(fn node -> Map.get(node, "id", Map.get(node, :id, "")) end)
  end

  defp find_terminals(nodes) do
    Enum.filter(nodes, fn node ->
      type = Map.get(node, "type", Map.get(node, :type, ""))
      type in ["push", "terminal", "PUSH"]
    end)
    |> Enum.map(fn node -> Map.get(node, "id", Map.get(node, :id, "")) end)
  end

  defp find_security_gates(nodes) do
    Enum.filter(nodes, fn node ->
      type = Map.get(node, "type", Map.get(node, :type, ""))
      type in ["security_gate", "firewall"]
    end)
    |> Map.new(fn node ->
      id = Map.get(node, "id", Map.get(node, :id, ""))
      rules = Map.get(node, "config", %{}) |> Map.get("rules", [])
      {id, rules}
    end)
  end

  # ---------------------------------------------------------------------------
  # Path computation (BFS from source to terminals)
  # ---------------------------------------------------------------------------

  defp compute_all_paths(sources, terminals, adjacency, _node_index) do
    terminal_set = MapSet.new(terminals)

    Enum.flat_map(sources, fn source ->
      bfs_paths(source, terminal_set, adjacency)
    end)
  end

  defp bfs_paths(start, targets, adjacency) do
    bfs_paths_acc([[start]], targets, adjacency, [])
  end

  defp bfs_paths_acc([], _targets, _adjacency, found), do: found

  defp bfs_paths_acc([current_path | rest], targets, adjacency, found) do
    head = List.first(current_path)

    if MapSet.member?(targets, head) do
      bfs_paths_acc(rest, targets, adjacency, [Enum.reverse(current_path) | found])
    else
      neighbours = Map.get(adjacency, head, [])
      visited = MapSet.new(current_path)

      new_paths =
        neighbours
        |> Enum.reject(fn n -> MapSet.member?(visited, n) end)
        |> Enum.map(fn n -> [n | current_path] end)

      bfs_paths_acc(new_paths ++ rest, targets, adjacency, found)
    end
  end

  # ---------------------------------------------------------------------------
  # Packet simulation
  # ---------------------------------------------------------------------------

  defp simulate_packets(paths, security_gates, node_index, params) do
    :rand.seed(:exsplus, {params.seed, params.seed * 2, params.seed * 3})

    steps = params.duration_steps
    path_count = length(paths)

    {events, metrics} =
      Enum.reduce(1..steps, {[], %{sent: 0, delivered: 0, dropped: 0, total_latency: 0.0}}, fn step, {evts, met} ->
        # Select a path for this packet (round-robin across available paths)
        path = Enum.at(paths, rem(step - 1, path_count))
        source = List.first(path)
        target = List.last(path)
        timestamp = step / params.packet_rate

        packet_id = "pkt-#{step}"
        pkt_type = pick_packet_type()
        size = 64 + :rand.uniform(1400)
        encrypted = pkt_type in [:https, :dns]

        # Create send event
        send_event = %{
          type: :sent,
          packet_id: packet_id,
          timestamp: timestamp,
          metadata: %{
            source: source,
            target: target,
            packet_type: pkt_type,
            size: size,
            encrypted: encrypted
          }
        }

        # Check drop (network condition)
        dropped = :rand.uniform() < params.drop_rate

        if dropped do
          drop_event = %{
            type: :dropped,
            packet_id: packet_id,
            timestamp: timestamp + params.latency_ms / 1000 * 0.5,
            metadata: %{reason: "network_loss", source: source, target: target}
          }

          {[drop_event, send_event | evts], %{met | sent: met.sent + 1, dropped: met.dropped + 1}}
        else
          # Trace through each hop
          {hop_events, blocked} =
            trace_hops(packet_id, path, timestamp, params, security_gates, node_index)

          if blocked do
            block_event = %{
              type: :firewall_block,
              packet_id: packet_id,
              timestamp: timestamp + params.latency_ms / 1000,
              metadata: %{source: source, target: target, path: path}
            }

            {[block_event, send_event | hop_events ++ evts],
             %{met | sent: met.sent + 1, dropped: met.dropped + 1}}
          else
            latency =
              params.latency_ms + (:rand.uniform() * 2 - 1) * params.jitter_ms

            deliver_event = %{
              type: :delivered,
              packet_id: packet_id,
              timestamp: timestamp + latency / 1000,
              metadata: %{source: source, target: target, latency_ms: latency}
            }

            {[deliver_event, send_event | hop_events ++ evts],
             %{
               met
               | sent: met.sent + 1,
                 delivered: met.delivered + 1,
                 total_latency: met.total_latency + latency
             }}
          end
        end
      end)

    avg_latency =
      if metrics.delivered > 0,
        do: metrics.total_latency / metrics.delivered,
        else: 0.0

    throughput =
      if steps > 0,
        do: metrics.delivered / (steps / params.packet_rate),
        else: 0.0

    final_metrics = %{
      sent: metrics.sent,
      delivered: metrics.delivered,
      dropped: metrics.dropped,
      avg_latency: Float.round(avg_latency, 2),
      throughput: Float.round(throughput, 2)
    }

    {Enum.reverse(events), final_metrics}
  end

  defp trace_hops(packet_id, path, base_timestamp, params, security_gates, _node_index) do
    hops = path |> Enum.chunk_every(2, 1, :discard)

    Enum.reduce(hops, {[], false}, fn
      _, {evts, true} ->
        # Already blocked — skip remaining hops
        {evts, true}

      [from, to], {evts, false} ->
        hop_time = base_timestamp + length(evts) * (params.latency_ms / 1000 / length(hops))

        hop_event = %{
          type: :hop,
          packet_id: packet_id,
          timestamp: hop_time,
          metadata: %{from: from, to: to}
        }

        # Check if this hop passes through a security gate
        blocked =
          Map.has_key?(security_gates, to) and
            not passes_security_gate(security_gates[to])

        {[hop_event | evts], blocked}
    end)
  end

  defp passes_security_gate(rules) when is_list(rules) do
    # For MVP: security gates pass unless they have explicit "deny all" rules
    not Enum.any?(rules, fn rule ->
      Map.get(rule, "action", "") == "deny" and Map.get(rule, "target", "") == "*"
    end)
  end

  defp passes_security_gate(_), do: true

  defp pick_packet_type do
    types = [:http, :https, :tcp, :udp, :icmp, :dns]
    weights = [30, 40, 15, 10, 2, 3]

    total = Enum.sum(weights)
    pick = :rand.uniform(total)

    Enum.zip(types, weights)
    |> Enum.reduce_while(0, fn {type, weight}, acc ->
      new_acc = acc + weight
      if pick <= new_acc, do: {:halt, type}, else: {:cont, new_acc}
    end)
  end

  # ---------------------------------------------------------------------------
  # Security analysis
  # ---------------------------------------------------------------------------

  defp detect_security_issues(events, security_gates, nodes) do
    findings = []

    # Check for unencrypted traffic through security-sensitive paths
    unencrypted_count =
      Enum.count(events, fn evt ->
        evt.type == :delivered and
          not Map.get(evt.metadata, :encrypted, true)
      end)

    findings =
      if unencrypted_count > 0 do
        [
          %{
            severity: "medium",
            message: "#{unencrypted_count} unencrypted packets traversed the pipeline",
            recommendation: "Add TLS/HTTPS enforcement before push nodes"
          }
          | findings
        ]
      else
        findings
      end

    # Check for missing security gates before terminals
    terminal_nodes =
      Enum.filter(nodes, fn n ->
        Map.get(n, "type", Map.get(n, :type, "")) in ["push", "terminal", "PUSH"]
      end)

    findings =
      if length(terminal_nodes) > 0 and map_size(security_gates) == 0 do
        [
          %{
            severity: "high",
            message: "no security gates in pipeline — packets flow unfiltered to push targets",
            recommendation: "Add a security_gate node before push nodes"
          }
          | findings
        ]
      else
        findings
      end

    # Check for firewall blocks
    block_count = Enum.count(events, fn evt -> evt.type == :firewall_block end)

    findings =
      if block_count > 0 do
        [
          %{
            severity: "info",
            message: "#{block_count} packets blocked by security gates (expected if rules are correct)",
            recommendation: "Review security gate rules if blocks are unexpected"
          }
          | findings
        ]
      else
        findings
      end

    findings
  end
end
