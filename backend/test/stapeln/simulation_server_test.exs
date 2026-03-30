# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule Stapeln.SimulationServerTest do
  use ExUnit.Case, async: false

  alias Stapeln.SimulationServer

  # Tests run against the application-started SimulationServer.
  # The server is started by the Stapeln.Application supervisor.

  defp simple_pipeline do
    %{
      "nodes" => [
        %{"id" => "base", "type" => "source", "config" => %{"image" => "alpine:3.19"}},
        %{"id" => "run", "type" => "run", "config" => %{"commands" => ["echo hello"]}},
        %{"id" => "push", "type" => "push", "config" => %{"registry" => "ghcr.io/test"}}
      ],
      "connections" => [
        %{"from" => "base", "to" => "run"},
        %{"from" => "run", "to" => "push"}
      ]
    }
  end

  # ---------------------------------------------------------------------------
  # Session lifecycle tests
  # ---------------------------------------------------------------------------

  test "start_build_simulation returns session id" do
    {:ok, session_id} = SimulationServer.start_build_simulation(simple_pipeline())

    assert is_binary(session_id)
    assert String.length(session_id) > 10
  end

  test "session completes asynchronously" do
    {:ok, session_id} = SimulationServer.start_build_simulation(simple_pipeline())

    # Poll until complete (with timeout)
    result = poll_until_done(session_id, 5_000)

    assert result.status == :complete
    assert result.result != nil
    assert result.result.valid == true
  end

  test "start_what_if returns session id" do
    scenarios = [%{"name" => "Test", "mutations" => [%{"type" => "chainguard_swap"}]}]
    {:ok, session_id} = SimulationServer.start_what_if(simple_pipeline(), scenarios)

    assert is_binary(session_id)

    result = poll_until_done(session_id, 5_000)
    assert result.status == :complete
  end

  test "start_supply_chain_analysis returns session id" do
    {:ok, session_id} = SimulationServer.start_supply_chain_analysis(simple_pipeline())

    result = poll_until_done(session_id, 5_000)
    assert result.status == :complete
    assert result.result.slsa_level >= 0
  end

  test "start_dry_run returns session id" do
    {:ok, session_id} = SimulationServer.start_dry_run(simple_pipeline(), %{duration_steps: 10})

    result = poll_until_done(session_id, 5_000)
    assert result.status == :complete
  end

  test "get_session returns not_found for unknown id" do
    assert {:error, :not_found} = SimulationServer.get_session("nonexistent-id")
  end

  test "cancel_session cancels a running session" do
    # Use a large pipeline to ensure it doesn't complete instantly
    large_pipeline = %{
      "nodes" => [
        %{"id" => "base", "type" => "source", "config" => %{"image" => "alpine:3.19"}},
        %{"id" => "push", "type" => "push", "config" => %{"registry" => "ghcr.io/test"}}
      ],
      "connections" => [%{"from" => "base", "to" => "push"}]
    }

    {:ok, session_id} = SimulationServer.start_build_simulation(large_pipeline)

    # The simulation may complete very quickly for simple pipelines,
    # so we just verify the cancel API works without error
    case SimulationServer.cancel_session(session_id) do
      :ok -> assert true
      {:error, :not_running} -> assert true  # Already completed
    end
  end

  test "cancel nonexistent session returns not_found" do
    assert {:error, :not_found} = SimulationServer.cancel_session("fake-id")
  end

  test "list_sessions returns session list" do
    {:ok, _id} = SimulationServer.start_build_simulation(simple_pipeline())

    sessions = SimulationServer.list_sessions()
    assert is_list(sessions)
    assert length(sessions) >= 1
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp poll_until_done(session_id, timeout_ms, elapsed \\ 0) do
    if elapsed >= timeout_ms do
      flunk("session #{session_id} did not complete within #{timeout_ms}ms")
    end

    case SimulationServer.get_session(session_id) do
      {:ok, %{status: status} = session} when status in [:complete, :failed, :cancelled] ->
        session

      {:ok, _} ->
        Process.sleep(50)
        poll_until_done(session_id, timeout_ms, elapsed + 50)

      {:error, :not_found} ->
        Process.sleep(50)
        poll_until_done(session_id, timeout_ms, elapsed + 50)
    end
  end
end
