# SPDX-License-Identifier: MPL-2.0

import Config

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:container_id]

# Import environment specific config
import_config "#{config_env()}.exs"
