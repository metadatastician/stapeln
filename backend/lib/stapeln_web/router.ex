defmodule StapelnWeb.Router do
  use StapelnWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :api_authenticated do
    plug StapelnWeb.Plugs.RequireApiToken
  end

  scope "/api", StapelnWeb do
    pipe_through :api

    get "/healthz", HealthController, :show
    post "/auth/register", AuthController, :register
    post "/auth/login", AuthController, :login
  end

  scope "/api", StapelnWeb do
    pipe_through [:api, :api_authenticated]

    get "/stacks", StackController, :index
    post "/stacks", StackController, :create
    get "/stacks/:id", StackController, :show
    put "/stacks/:id", StackController, :update
    post "/stacks/:id/validate", StackController, :validate
    post "/stacks/:id/security-scan", StackController, :security_scan
    post "/stacks/:id/gap-analysis", StackController, :gap_analysis
    post "/stacks/:id/generate", StackController, :generate
    post "/stacks/:id/sign", StackController, :sign_stack
    get "/stacks/:id/verify", StackController, :verify_stack
    get "/audit", AuditController, :index
    get "/auth/me", AuthController, :me
    get "/settings", SettingsController, :show
    put "/settings", SettingsController, :update

    # Ephemeral pinhole firewall management
    post "/firewall/pinholes", FirewallController, :create
    get "/firewall/pinholes", FirewallController, :index
    delete "/firewall/pinholes/:id", FirewallController, :delete
    post "/firewall/check", FirewallController, :check

    post "/security/panic-attacker", SecurityController, :start
    post "/security/panic-attacker/stop", SecurityController, :stop
    get "/security/panic-attacker/status", SecurityController, :status

    # Simulation engine endpoints (build sim, what-if, supply chain)
    post "/simulations/build", SimulationController, :build
    post "/simulations/what-if", SimulationController, :what_if
    post "/simulations/suggest", SimulationController, :suggest
    post "/simulations/supply-chain", SimulationController, :supply_chain
    post "/simulations/sessions", SimulationController, :create_session
    get "/simulations/sessions", SimulationController, :list_sessions
    get "/simulations/sessions/:id", SimulationController, :show_session
    delete "/simulations/sessions/:id", SimulationController, :cancel_session

    # Assembly pipeline operations
    post "/pipelines/validate", PipelineController, :validate
    post "/pipelines/generate", PipelineController, :generate
    post "/pipelines/optimize", PipelineController, :optimize
    post "/pipelines/dry-run", PipelineController, :dry_run
    get "/pipelines/templates", PipelineController, :templates
    post "/pipelines", PipelineController, :create
    get "/pipelines/:id", PipelineController, :show
    put "/pipelines/:id", PipelineController, :update
    delete "/pipelines/:id", PipelineController, :delete
  end

  scope "/api" do
    pipe_through [:api, :api_authenticated]
    forward "/graphql", Absinthe.Plug, schema: StapelnWeb.Schema
  end
end
