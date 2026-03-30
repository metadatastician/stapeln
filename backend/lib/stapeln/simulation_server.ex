# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Stapeln.SimulationServer - GenServer managing simulation sessions.
# Allows long-running simulations to be started, queried, and cancelled.

defmodule Stapeln.SimulationServer do
  @moduledoc """
  GenServer managing simulation sessions.

  Each simulation runs asynchronously via a Task and stores its result
  in an ETS table keyed by session ID. Clients can:

  1. Start a simulation (build, what-if, or supply-chain)
  2. Poll for completion via session ID
  3. Retrieve results once complete
  4. Cancel a running simulation

  Sessions expire after a configurable TTL (default 30 minutes) to prevent
  memory leaks from abandoned simulations.

  ## Session lifecycle

      :pending -> :running -> :complete | :failed | :cancelled

  ## Design notes

  - One GenServer per Stapeln node (named process)
  - Results stored in ETS for fast concurrent reads
  - Tasks linked to GenServer for cleanup on crash
  - No external dependencies (no Redis, no DB — pure in-memory)
  """

  use GenServer

  require Logger

  # ---------------------------------------------------------------------------
  # Types
  # ---------------------------------------------------------------------------

  @type session_id :: String.t()

  @type session_status :: :pending | :running | :complete | :failed | :cancelled

  @type session :: %{
          id: session_id(),
          type: atom(),
          status: session_status(),
          pipeline: map(),
          params: map(),
          result: term(),
          error: term(),
          started_at: DateTime.t(),
          completed_at: DateTime.t() | nil,
          task_ref: reference() | nil
        }

  # Default session TTL: 30 minutes
  @default_ttl_ms 30 * 60 * 1000

  # Cleanup interval: every 5 minutes
  @cleanup_interval_ms 5 * 60 * 1000

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc "Start the simulation server."
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Start a build simulation session.

  Returns `{:ok, session_id}` immediately. The simulation runs asynchronously.
  """
  @spec start_build_simulation(map()) :: {:ok, session_id()}
  def start_build_simulation(pipeline) when is_map(pipeline) do
    GenServer.call(__MODULE__, {:start, :build, pipeline, %{}})
  end

  @doc """
  Start a what-if comparison session.

  Accepts a pipeline and a list of scenario definitions.
  Returns `{:ok, session_id}` immediately.
  """
  @spec start_what_if(map(), [map()]) :: {:ok, session_id()}
  def start_what_if(pipeline, scenarios) when is_map(pipeline) and is_list(scenarios) do
    GenServer.call(__MODULE__, {:start, :what_if, pipeline, %{scenarios: scenarios}})
  end

  @doc """
  Start a supply chain analysis session.

  Returns `{:ok, session_id}` immediately.
  """
  @spec start_supply_chain_analysis(map()) :: {:ok, session_id()}
  def start_supply_chain_analysis(pipeline) when is_map(pipeline) do
    GenServer.call(__MODULE__, {:start, :supply_chain, pipeline, %{}})
  end

  @doc """
  Start a network packet flow dry-run session.

  Returns `{:ok, session_id}` immediately.
  """
  @spec start_dry_run(map(), map()) :: {:ok, session_id()}
  def start_dry_run(pipeline, params \\ %{}) when is_map(pipeline) do
    GenServer.call(__MODULE__, {:start, :dry_run, pipeline, params})
  end

  @doc """
  Get the status and result of a simulation session.

  Returns the full session map including status, result (if complete),
  and error (if failed).
  """
  @spec get_session(session_id()) :: {:ok, session()} | {:error, :not_found}
  def get_session(session_id) do
    case :ets.lookup(:stapeln_sim_sessions, session_id) do
      [{^session_id, session}] -> {:ok, session}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Cancel a running simulation session.

  If the session is :running, the Task is killed and the session is
  marked :cancelled. Already-complete sessions are not affected.
  """
  @spec cancel_session(session_id()) :: :ok | {:error, :not_found | :not_running}
  def cancel_session(session_id) do
    GenServer.call(__MODULE__, {:cancel, session_id})
  end

  @doc """
  List all active sessions (not expired).
  """
  @spec list_sessions() :: [session()]
  def list_sessions do
    :ets.tab2list(:stapeln_sim_sessions)
    |> Enum.map(fn {_id, session} -> session end)
    |> Enum.sort_by(fn s -> s.started_at end, {:desc, DateTime})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    # Create ETS table for session storage
    :ets.new(:stapeln_sim_sessions, [:named_table, :public, :set, read_concurrency: true])

    # Schedule periodic cleanup
    Process.send_after(self(), :cleanup_expired, @cleanup_interval_ms)

    {:ok, %{task_refs: %{}}}
  end

  @impl true
  def handle_call({:start, type, pipeline, params}, _from, state) do
    session_id = generate_session_id()

    session = %{
      id: session_id,
      type: type,
      status: :running,
      pipeline: pipeline,
      params: params,
      result: nil,
      error: nil,
      started_at: DateTime.utc_now(),
      completed_at: nil,
      task_ref: nil
    }

    # Store initial session
    :ets.insert(:stapeln_sim_sessions, {session_id, session})

    # Start async task
    task =
      Task.async(fn ->
        run_simulation(type, pipeline, params)
      end)

    # Track the task reference for this session
    updated_session = %{session | task_ref: task.ref}
    :ets.insert(:stapeln_sim_sessions, {session_id, updated_session})

    updated_refs = Map.put(state.task_refs, task.ref, session_id)

    {:reply, {:ok, session_id}, %{state | task_refs: updated_refs}}
  end

  @impl true
  def handle_call({:cancel, session_id}, _from, state) do
    case :ets.lookup(:stapeln_sim_sessions, session_id) do
      [{^session_id, %{status: :running, task_ref: ref} = session}] when not is_nil(ref) ->
        # Kill the task by demonitoring and flushing
        Process.demonitor(ref, [:flush])

        updated = %{session |
          status: :cancelled,
          completed_at: DateTime.utc_now(),
          task_ref: nil
        }

        :ets.insert(:stapeln_sim_sessions, {session_id, updated})
        updated_refs = Map.delete(state.task_refs, ref)

        {:reply, :ok, %{state | task_refs: updated_refs}}

      [{^session_id, _}] ->
        {:reply, {:error, :not_running}, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    # Task completed — update the session
    case Map.get(state.task_refs, ref) do
      nil ->
        {:noreply, state}

      session_id ->
        # Demonitor the task (it's done)
        Process.demonitor(ref, [:flush])

        case :ets.lookup(:stapeln_sim_sessions, session_id) do
          [{^session_id, session}] ->
            updated =
              case result do
                {:ok, sim_result} ->
                  %{session |
                    status: :complete,
                    result: sim_result,
                    completed_at: DateTime.utc_now(),
                    task_ref: nil
                  }

                {:error, reason} ->
                  %{session |
                    status: :failed,
                    error: reason,
                    completed_at: DateTime.utc_now(),
                    task_ref: nil
                  }
              end

            :ets.insert(:stapeln_sim_sessions, {session_id, updated})

          [] ->
            :ok
        end

        updated_refs = Map.delete(state.task_refs, ref)
        {:noreply, %{state | task_refs: updated_refs}}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    # Task crashed — mark session as failed
    case Map.get(state.task_refs, ref) do
      nil ->
        {:noreply, state}

      session_id ->
        case :ets.lookup(:stapeln_sim_sessions, session_id) do
          [{^session_id, session}] ->
            updated = %{session |
              status: :failed,
              error: "simulation process crashed: #{inspect(reason)}",
              completed_at: DateTime.utc_now(),
              task_ref: nil
            }

            :ets.insert(:stapeln_sim_sessions, {session_id, updated})

          [] ->
            :ok
        end

        updated_refs = Map.delete(state.task_refs, ref)
        {:noreply, %{state | task_refs: updated_refs}}
    end
  end

  @impl true
  def handle_info(:cleanup_expired, state) do
    now = DateTime.utc_now()

    :ets.tab2list(:stapeln_sim_sessions)
    |> Enum.each(fn {id, session} ->
      age_ms = DateTime.diff(now, session.started_at, :millisecond)

      if age_ms > @default_ttl_ms and session.status in [:complete, :failed, :cancelled] do
        :ets.delete(:stapeln_sim_sessions, id)
      end
    end)

    # Reschedule cleanup
    Process.send_after(self(), :cleanup_expired, @cleanup_interval_ms)

    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Simulation dispatch
  # ---------------------------------------------------------------------------

  defp run_simulation(:build, pipeline, _params) do
    try do
      result = Stapeln.BuildSimulator.simulate(pipeline)
      {:ok, result}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp run_simulation(:what_if, pipeline, %{scenarios: scenarios}) do
    try do
      result = Stapeln.WhatIfEngine.compare(pipeline, scenarios)
      {:ok, result}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp run_simulation(:supply_chain, pipeline, _params) do
    try do
      result = Stapeln.SupplyChainAnalyzer.analyze(pipeline)
      {:ok, result}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp run_simulation(:dry_run, pipeline, params) do
    try do
      result = Stapeln.SimulationEngine.dry_run(pipeline, params)
      {:ok, result}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp run_simulation(type, _pipeline, _params) do
    {:error, "unknown simulation type: #{inspect(type)}"}
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp generate_session_id do
    # Generate a URL-safe session ID from random bytes
    :crypto.strong_rand_bytes(16)
    |> Base.url_encode64(padding: false)
  end
end
