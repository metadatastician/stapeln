# SPDX-License-Identifier: MPL-2.0
import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :stapeln, StapelnWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "09oxWpFg/+JTtpvubG7IZv5NdfROklSAyHoqBUqY2akbAZId6Zf83GVifWDbML5o",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

config :stapeln, :api_auth,
  enabled: true,
  token: "test-stapeln-token"

# Keep the user store purely in memory during tests.
#
# It defaults to /tmp/stapeln-user-store.json, which survives between runs --
# and the auth tests build addresses from System.unique_integer/1, which is
# unique WITHIN a VM but restarts low on every run. A run that wrote
# test-3@example.com left it on disk, and a later run reissuing the same low
# integer failed with {:error, :email_taken}. Intermittently, which is why it
# went undiagnosed. /tmp is shared between concurrent jobs too, so the file was
# also a cross-process channel between async: true tests.
config :stapeln, Stapeln.Auth.UserStore, persist_path: nil
