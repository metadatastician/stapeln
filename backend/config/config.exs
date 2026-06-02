# SPDX-License-Identifier: MPL-2.0
# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :stapeln, []

# VeriSimDB instance for stapeln data (port 8093)
# Set VERISIMDB_URL=http://localhost:8093 in your environment

config :stapeln, :api_auth,
  enabled: true,
  token: nil

# Configure the endpoint
config :stapeln, StapelnWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: StapelnWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Stapeln.PubSub,
  live_view: [signing_salt: "sGbvQkwh"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
