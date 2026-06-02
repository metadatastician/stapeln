# SPDX-License-Identifier: MPL-2.0
# Stapeln — Sonnet session brief

**Model:** Claude Sonnet
**Repo:** `fleet-ecosystem/stapeln` (at `/var/mnt/eclipse/repos/fleet-ecosystem/stapeln`)
**Tasks:** DB-1, DB-2, DB-4, A-1, A-2, A-3, WS-1, C-2
**Prerequisite:** Haiku session complete — VeriSimDB must be running on port 8093

---

## Context

Stapeln is an Elixir/Phoenix backend + ReScript frontend container-management GUI.

Persistence uses `Stapeln.DbStore` (`backend/lib/stapeln/db_store.ex`) which wraps
VeriSimDB (port 8093). Two stores bypass the VeriSimDB path and go to in-memory
GenServer directly — your job is to wire them properly and remove the dead fallbacks.

Auth tokens are generated but never sent by the frontend. A Phoenix WebSocket channel
definition is missing despite the frontend client being ready.

Key files:
- `backend/lib/stapeln/db_store.ex` — VeriSimDB CRUD (stacks, users)
- `backend/lib/stapeln/native_bridge.ex` — wiring for stacks (has the VeriSimDB guard pattern to copy)
- `backend/lib/stapeln_web/controllers/settings_controller.ex` — hits SettingsStore directly
- `backend/lib/stapeln_web/controllers/pipeline_controller.ex` — hits PipelineStore directly
- `frontend/src/ApiClient.res` — REST client, no auth header sent
- `frontend/src/LoginPage.res` — logs in but doesn't store the token pair
- `frontend/src/Socket.res` — WebSocket client, channel not yet defined in Elixir

---

## DB-1 — Wire SettingsStore → VeriSimDB

Add to `db_store.ex`:
```elixir
def get_settings(user_id) do
  case Client.get_octad("settings:#{user_id}") do
    {:ok, octad} -> {:ok, octad.data}
    {:error, :not_found} -> {:ok, %{}}   # empty settings is valid
    err -> err
  end
end

def update_settings(user_id, attrs) do
  Client.upsert_octad("settings:#{user_id}", %{type: "settings", data: attrs})
end
```

Update `settings_controller.ex` to use the guard pattern from `native_bridge.ex`:
```elixir
if DbStore.available?() do
  DbStore.get_settings(user_id)
else
  SettingsStore.get()
end
```

---

## DB-2 — Wire PipelineStore → VeriSimDB

Add to `db_store.ex`:
```elixir
def list_pipelines/0, def get_pipeline/1, def create_pipeline/1,
def update_pipeline/2, def delete_pipeline/1
```

Using octad type `"pipelines"`. Update `pipeline_controller.ex` to use the guard
pattern for all four operations (create/get/update/delete).

---

## DB-4 — Delete GenServer fallback stores

Once DB-1 and DB-2 pass tests, delete:
- `backend/lib/stapeln/stack_store.ex`
- `backend/lib/stapeln/settings_store.ex`
- `backend/lib/stapeln/pipeline_store.ex`

Remove their aliases from any importing file. Do NOT delete `user_store.ex` — auth
still needs it. Run `mix compile` (must be warning-free) and `mix test` (must be
105/105).

---

## A-1 — LoginPage wires to refresh token endpoint

In `frontend/src/LoginPage.res`, change the POST target from `/api/auth/login` to
`/api/auth/login_with_refresh`. The response is now:
```json
{"access_token": "...", "refresh_token": "...", "token_type": "Bearer", "expires_in": 604800}
```

Store both tokens (use `localStorage` via the existing `WebAPI.res` DOM bindings or
equivalent). Update the success handler to read from `access_token` field.

---

## A-2 — ApiClient sends Authorization header

In `frontend/src/ApiClient.res`, add a helper that reads the stored access token and
injects `Authorization: Bearer <token>` on every request to a protected endpoint.
All calls to stacks, security, simulation, pipelines, settings, and audit must use it.

---

## A-3 — Handle 401 in ApiClient

Add a 401 interceptor: on 401 response, attempt one token refresh via
`POST /api/auth/refresh` with the stored refresh token. On success, retry the
original request with the new access token and store the new pair. On failure,
clear stored tokens and send the user to the login view.

Guard the retry: track a `refreshing` boolean so a failed refresh does not
itself trigger another refresh attempt (no infinite loop).

Wire failure messaging through `ConversationalError.res`.

---

## WS-1 — Phoenix channel definition

Create two files:

**`backend/lib/stapeln_web/channels/user_socket.ex`**
```elixir
# SPDX-License-Identifier: MPL-2.0
defmodule StapelnWeb.UserSocket do
  use Phoenix.Socket
  channel "events:*", StapelnWeb.EventsChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Stapeln.Auth.Token.verify(token) do
      {:ok, user_id} -> {:ok, assign(socket, :user_id, user_id)}
      _ -> :error
    end
  end

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"
end
```

**`backend/lib/stapeln_web/channels/events_channel.ex`**
```elixir
# SPDX-License-Identifier: MPL-2.0
defmodule StapelnWeb.EventsChannel do
  use Phoenix.Channel

  def join("events:" <> _topic, _params, socket), do: {:ok, socket}

  def handle_in("ping", _payload, socket) do
    {:reply, {:ok, %{response: "pong"}}, socket}
  end
end
```

Wire `UserSocket` into `backend/lib/stapeln_web/endpoint.ex`:
```elixir
socket "/socket", StapelnWeb.UserSocket,
  websocket: true,
  longpoll: false
```

---

## C-2 — Rust test signal in CI

Create `.github/workflows/rust-tests.yml`:

```yaml
# SPDX-License-Identifier: MPL-2.0
name: Rust tests

on: [push, pull_request]

permissions: read-all

jobs:
  rust-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd
      - uses: dtolnay/rust-toolchain@4be9e76fd7c4901c61fb841f559994984270fce7
        with:
          toolchain: stable
      - uses: Swatinem/rust-cache@779680da715d629ac1d338a641029a2f4372abb5
      - name: Test vordr
        run: cargo test --manifest-path container-stack/vordr/src/rust/Cargo.toml
      - name: Test selur
        run: cargo test --manifest-path container-stack/selur/Cargo.toml
```

---

## Done

```bash
cd backend && mix compile    # 0 warnings
cd backend && mix test       # 105/105
cd .. && just e2e            # 0 failures
```

Commit:
```
fix(stapeln): Sonnet session — VeriSimDB wiring, auth token flow, WS channel stub, Rust CI

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
```

Push to `origin main`.
