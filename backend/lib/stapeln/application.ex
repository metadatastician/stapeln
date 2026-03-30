# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule Stapeln.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      StapelnWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:stapeln, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Stapeln.PubSub},
      Stapeln.StackStore,
      Stapeln.PipelineStore,
      Stapeln.Auth.UserStore,
      Stapeln.SettingsStore,
      Stapeln.Firewall.PinholeManager,
      Stapeln.SimulationServer,
      {Task.Supervisor, name: Stapeln.TaskSupervisor},
      StapelnWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Stapeln.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    StapelnWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
