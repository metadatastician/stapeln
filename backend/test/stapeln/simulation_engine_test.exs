# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule Stapeln.SimulationEngineTest do
  use ExUnit.Case, async: false

  alias Stapeln.SimulationEngine

  # ---------------------------------------------------------------------------
  # Test fixtures
  # ---------------------------------------------------------------------------

  defp simple_pipeline do
    %{
      "nodes" => [
        %{"id" => "src", "type" => "source", "config" => %{"image" => "alpine:3.19"}},
        %{"id" => "build", "type" => "run", "config" => %{"command" => "make build"}},
        %{"id" => "push", "type" => "push", "config" => %{"registry" => "ghcr.io/hyperpolymath"}}
      ],
      "connections" => [
        %{"from" => "src", "to" => "build"},
        %{"from" => "build", "to" => "push"}
      ]
    }
  end

  defp pipeline_with_security_gate do
    %{
      "nodes" => [
        %{"id" => "src", "type" => "source", "config" => %{"image" => "chainguard/wolfi-base:latest"}},
        %{"id" => "build", "type" => "run", "config" => %{"command" => "cargo build --release"}},
        %{"id" => "gate", "type" => "security_gate", "config" => %{"rules" => [%{"action" => "allow", "target" => "*"}]}},
        %{"id" => "push", "type" => "push", "config" => %{"registry" => "ghcr.io/hyperpolymath"}}
      ],
      "connections" => [
        %{"from" => "src", "to" => "build"},
        %{"from" => "build", "to" => "gate"},
        %{"from" => "gate", "to" => "push"}
      ]
    }
  end

  defp pipeline_with_deny_all_gate do
    %{
      "nodes" => [
        %{"id" => "src", "type" => "source", "config" => %{"image" => "alpine:3.19"}},
        %{"id" => "gate", "type" => "security_gate", "config" => %{"rules" => [%{"action" => "deny", "target" => "*"}]}},
        %{"id" => "push", "type" => "push", "config" => %{"registry" => "ghcr.io/hyperpolymath"}}
      ],
      "connections" => [
        %{"from" => "src", "to" => "gate"},
        %{"from" => "gate", "to" => "push"}
      ]
    }
  end

  defp branching_pipeline do
    %{
      "nodes" => [
        %{"id" => "src", "type" => "source", "config" => %{"image" => "alpine:3.19"}},
        %{"id" => "test", "type" => "run", "config" => %{"command" => "make test"}},
        %{"id" => "build", "type" => "run", "config" => %{"command" => "make build"}},
        %{"id" => "push1", "type" => "push", "config" => %{"registry" => "ghcr.io"}},
        %{"id" => "push2", "type" => "push", "config" => %{"registry" => "docker.io"}}
      ],
      "connections" => [
        %{"from" => "src", "to" => "test"},
        %{"from" => "src", "to" => "build"},
        %{"from" => "test", "to" => "push1"},
        %{"from" => "build", "to" => "push2"}
      ]
    }
  end

  defp disconnected_pipeline do
    %{
      "nodes" => [
        %{"id" => "src", "type" => "source", "config" => %{"image" => "alpine:3.19"}},
        %{"id" => "orphan", "type" => "run", "config" => %{"command" => "echo hi"}},
        %{"id" => "push", "type" => "push", "config" => %{"registry" => "ghcr.io"}}
      ],
      "connections" => [
        %{"from" => "src", "to" => "push"}
      ]
    }
  end

  defp empty_pipeline do
    %{"nodes" => [], "connections" => []}
  end

  # ---------------------------------------------------------------------------
  # Basic dry-run tests
  # ---------------------------------------------------------------------------

  test "dry-run simple pipeline produces events" do
    result = SimulationEngine.dry_run(simple_pipeline(), %{duration_steps: 20, seed: 42})

    assert result.packets_sent == 20
    assert result.packets_sent == result.packets_delivered + result.packets_dropped
    assert length(result.events) > 0
    assert result.avg_latency_ms >= 0.0
    assert result.throughput >= 0.0
    assert result.validation.valid
  end

  test "dry-run with deterministic seed produces identical results" do
    params = %{duration_steps: 50, seed: 12345}
    result1 = SimulationEngine.dry_run(simple_pipeline(), params)
    result2 = SimulationEngine.dry_run(simple_pipeline(), params)

    assert result1.packets_sent == result2.packets_sent
    assert result1.packets_delivered == result2.packets_delivered
    assert result1.packets_dropped == result2.packets_dropped
    assert result1.avg_latency_ms == result2.avg_latency_ms
  end

  test "dry-run empty pipeline returns invalid" do
    result = SimulationEngine.dry_run(empty_pipeline())

    assert result.valid == false
    assert result.packets_sent == 0
    assert length(result.blockers) > 0
  end

  # ---------------------------------------------------------------------------
  # Security gate tests
  # ---------------------------------------------------------------------------

  test "dry-run with allow-all security gate delivers packets" do
    result = SimulationEngine.dry_run(pipeline_with_security_gate(), %{duration_steps: 30, seed: 42, drop_rate: 0.0})

    assert result.packets_delivered > 0
    assert result.packets_delivered == result.packets_sent
  end

  test "dry-run with deny-all security gate blocks packets" do
    result = SimulationEngine.dry_run(pipeline_with_deny_all_gate(), %{duration_steps: 30, seed: 42, drop_rate: 0.0})

    assert result.packets_dropped == result.packets_sent
    assert result.packets_delivered == 0
  end

  test "pipeline without security gates produces security finding" do
    result = SimulationEngine.dry_run(simple_pipeline(), %{duration_steps: 10, seed: 42})

    assert Enum.any?(result.security_findings, fn f ->
      f.severity == "high" and String.contains?(f.message, "no security gates")
    end)
  end

  # ---------------------------------------------------------------------------
  # Branching pipeline tests
  # ---------------------------------------------------------------------------

  test "dry-run branching pipeline uses multiple paths" do
    result = SimulationEngine.dry_run(branching_pipeline(), %{duration_steps: 40, seed: 42, drop_rate: 0.0})

    assert result.packets_sent == 40
    # Should have events targeting both push1 and push2
    targets =
      result.events
      |> Enum.filter(fn e -> e.type == :delivered end)
      |> Enum.map(fn e -> e.metadata.target end)
      |> MapSet.new()

    assert MapSet.size(targets) >= 1
  end

  # ---------------------------------------------------------------------------
  # Network condition tests
  # ---------------------------------------------------------------------------

  test "dry-run with zero drop rate delivers all packets" do
    result = SimulationEngine.dry_run(simple_pipeline(), %{
      duration_steps: 50,
      seed: 42,
      drop_rate: 0.0,
      jitter_ms: 0.0
    })

    assert result.packets_delivered == result.packets_sent
    assert result.packets_dropped == 0
  end

  test "dry-run with high drop rate drops most packets" do
    result = SimulationEngine.dry_run(simple_pipeline(), %{
      duration_steps: 100,
      seed: 42,
      drop_rate: 0.9
    })

    # With 90% drop rate, most packets should be dropped
    assert result.packets_dropped > result.packets_delivered
  end

  test "dry-run with high latency increases avg_latency_ms" do
    low_latency = SimulationEngine.dry_run(simple_pipeline(), %{
      duration_steps: 50,
      seed: 42,
      latency_ms: 10.0,
      drop_rate: 0.0
    })

    high_latency = SimulationEngine.dry_run(simple_pipeline(), %{
      duration_steps: 50,
      seed: 42,
      latency_ms: 500.0,
      drop_rate: 0.0
    })

    assert high_latency.avg_latency_ms > low_latency.avg_latency_ms
  end

  # ---------------------------------------------------------------------------
  # Event structure tests
  # ---------------------------------------------------------------------------

  test "events have required fields" do
    result = SimulationEngine.dry_run(simple_pipeline(), %{duration_steps: 5, seed: 42})

    for event <- result.events do
      assert Map.has_key?(event, :type)
      assert Map.has_key?(event, :packet_id)
      assert Map.has_key?(event, :timestamp)
      assert Map.has_key?(event, :metadata)
      assert is_atom(event.type)
      assert is_binary(event.packet_id)
      assert is_float(event.timestamp) or is_integer(event.timestamp)
    end
  end

  test "sent events include packet metadata" do
    result = SimulationEngine.dry_run(simple_pipeline(), %{duration_steps: 5, seed: 42})

    sent_events = Enum.filter(result.events, fn e -> e.type == :sent end)
    assert length(sent_events) == 5

    for evt <- sent_events do
      assert Map.has_key?(evt.metadata, :source)
      assert Map.has_key?(evt.metadata, :target)
      assert Map.has_key?(evt.metadata, :packet_type)
      assert Map.has_key?(evt.metadata, :size)
      assert evt.metadata.packet_type in [:http, :https, :tcp, :udp, :icmp, :dns]
    end
  end

  # ---------------------------------------------------------------------------
  # Validation integration
  # ---------------------------------------------------------------------------

  test "dry-run includes validation result" do
    result = SimulationEngine.dry_run(simple_pipeline(), %{duration_steps: 5})

    assert is_map(result.validation)
    assert result.validation.valid == true
    assert is_list(result.validation.errors)
  end

  test "invalid pipeline returns validation errors as blockers" do
    bad_pipeline = %{
      "nodes" => [
        %{"id" => "a", "type" => "unknown_type", "config" => %{}}
      ],
      "connections" => []
    }

    result = SimulationEngine.dry_run(bad_pipeline)
    assert result.valid == false
    assert length(result.blockers) > 0
  end
end
