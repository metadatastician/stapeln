# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# StapelnWeb.SimulationController - API controller for simulation engine endpoints.
# Wires up build simulation, what-if analysis, supply chain analysis, and session management.

defmodule StapelnWeb.SimulationController do
  use StapelnWeb, :controller

  alias Stapeln.BuildSimulator
  alias Stapeln.WhatIfEngine
  alias Stapeln.SupplyChainAnalyzer
  alias Stapeln.SimulationServer
  alias Stapeln.VeriSimDB

  # ---------------------------------------------------------------------------
  # Synchronous endpoints (immediate response)
  # ---------------------------------------------------------------------------

  @doc """
  POST /api/simulations/build — simulate a container build.

  Accepts a pipeline graph and returns layer manifest, timeline, supply chain
  info, security findings, and a Containerfile preview. Runs synchronously
  for pipelines with fewer than 50 nodes.
  """
  def build(conn, %{"pipeline" => pipeline}) when is_map(pipeline) do
    result = BuildSimulator.simulate(pipeline)

    VeriSimDB.record(:simulation, %{
      type: "build",
      valid: result.valid,
      total_size: result.total_size,
      total_time_ms: result.total_time_ms,
      security_score: result.security_score,
      layer_count: length(result.layers),
      finding_count: length(result.security_findings)
    })

    json(conn, %{data: result})
  end

  def build(conn, _params) do
    bad_request(conn, "missing required 'pipeline' object in request body")
  end

  @doc """
  POST /api/simulations/what-if — compare pipeline variants.

  Accepts a pipeline and a list of scenarios. Each scenario has a name
  and a list of mutations. Returns baseline result + scenario results
  with deltas.

  ## Request body

      {
        "pipeline": { ... },
        "scenarios": [
          {
            "name": "Switch to Chainguard",
            "mutations": [{"type": "chainguard_swap"}]
          }
        ]
      }
  """
  def what_if(conn, %{"pipeline" => pipeline, "scenarios" => scenarios})
      when is_map(pipeline) and is_list(scenarios) do
    result = WhatIfEngine.compare(pipeline, scenarios)

    VeriSimDB.record(:simulation, %{
      type: "what_if",
      scenario_count: length(scenarios),
      baseline_valid: result.baseline.valid,
      improved_count: Enum.count(result.scenarios, fn s -> s.delta.improved end)
    })

    json(conn, %{data: result})
  end

  def what_if(conn, %{"pipeline" => _pipeline}) do
    bad_request(conn, "missing required 'scenarios' array in request body")
  end

  def what_if(conn, _params) do
    bad_request(conn, "missing required 'pipeline' object and 'scenarios' array in request body")
  end

  @doc """
  POST /api/simulations/suggest — generate recommended what-if scenarios.

  Analyzes a pipeline and returns a list of improvement scenarios the user
  can select from in the UI.
  """
  def suggest(conn, %{"pipeline" => pipeline}) when is_map(pipeline) do
    suggestions = WhatIfEngine.suggest_scenarios(pipeline)
    json(conn, %{data: suggestions})
  end

  def suggest(conn, _params) do
    bad_request(conn, "missing required 'pipeline' object in request body")
  end

  @doc """
  POST /api/simulations/supply-chain — analyze supply chain integrity.

  Returns SLSA level assessment, risk score, image provenance, trust
  boundaries, and recommendations.
  """
  def supply_chain(conn, %{"pipeline" => pipeline}) when is_map(pipeline) do
    result = SupplyChainAnalyzer.analyze(pipeline)

    VeriSimDB.record(:simulation, %{
      type: "supply_chain",
      slsa_level: result.slsa_level,
      risk_score: result.risk_score,
      finding_count: length(result.findings),
      reproducible: result.reproducible
    })

    json(conn, %{data: result})
  end

  def supply_chain(conn, _params) do
    bad_request(conn, "missing required 'pipeline' object in request body")
  end

  # ---------------------------------------------------------------------------
  # Asynchronous session endpoints
  # ---------------------------------------------------------------------------

  @doc """
  POST /api/simulations/sessions — start an async simulation session.

  For large pipelines or multiple scenarios, use this endpoint to start
  the simulation asynchronously. Returns a session ID to poll for results.

  ## Request body

      {
        "type": "build" | "what_if" | "supply_chain" | "dry_run",
        "pipeline": { ... },
        "params": { ... }   // optional, type-specific parameters
      }
  """
  def create_session(conn, %{"type" => type, "pipeline" => pipeline} = params) when is_map(pipeline) do
    extra_params = Map.get(params, "params", %{})

    result =
      case type do
        "build" ->
          SimulationServer.start_build_simulation(pipeline)

        "what_if" ->
          scenarios = Map.get(extra_params, "scenarios", Map.get(params, "scenarios", []))
          SimulationServer.start_what_if(pipeline, scenarios)

        "supply_chain" ->
          SimulationServer.start_supply_chain_analysis(pipeline)

        "dry_run" ->
          SimulationServer.start_dry_run(pipeline, extra_params)

        _ ->
          {:error, "unknown simulation type '#{type}'; valid types: build, what_if, supply_chain, dry_run"}
      end

    case result do
      {:ok, session_id} ->
        conn
        |> put_status(:created)
        |> json(%{data: %{session_id: session_id, status: "running"}})

      {:error, message} ->
        bad_request(conn, message)
    end
  end

  def create_session(conn, _params) do
    bad_request(conn, "missing required 'type' and 'pipeline' in request body")
  end

  @doc """
  GET /api/simulations/sessions/:id — poll a simulation session.

  Returns the session status and result (if complete).
  """
  def show_session(conn, %{"id" => session_id}) do
    case SimulationServer.get_session(session_id) do
      {:ok, session} ->
        json(conn, %{data: serialize_session(session)})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "simulation session not found"})
    end
  end

  @doc """
  DELETE /api/simulations/sessions/:id — cancel a running simulation.
  """
  def cancel_session(conn, %{"id" => session_id}) do
    case SimulationServer.cancel_session(session_id) do
      :ok ->
        json(conn, %{data: %{cancelled: true, session_id: session_id}})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "simulation session not found"})

      {:error, :not_running} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "simulation is not running (already complete or cancelled)"})
    end
  end

  @doc """
  GET /api/simulations/sessions — list all active simulation sessions.
  """
  def list_sessions(conn, _params) do
    sessions =
      SimulationServer.list_sessions()
      |> Enum.map(&serialize_session/1)

    json(conn, %{data: sessions})
  end

  # ---------------------------------------------------------------------------
  # Serialization
  # ---------------------------------------------------------------------------

  defp serialize_session(session) do
    %{
      id: session.id,
      type: session.type,
      status: session.status,
      started_at: DateTime.to_iso8601(session.started_at),
      completed_at: if(session.completed_at, do: DateTime.to_iso8601(session.completed_at), else: nil),
      result: if(session.status == :complete, do: session.result, else: nil),
      error: if(session.status == :failed, do: session.error, else: nil)
    }
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp bad_request(conn, message) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: message})
  end
end
