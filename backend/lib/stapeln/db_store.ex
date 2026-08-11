# SPDX-License-Identifier: MPL-2.0
# db_store.ex - VeriSimDB-backed persistence layer for stapeln
#
# VeriSimDB octads persistence (port 8093).
# All data stored as octads in a single VeriSimDB instance (port 8093).
# Collections distinguished by metadata.collection field.

defmodule Stapeln.DbStore do
  @moduledoc """
  VeriSimDB-backed persistence layer.

  Provides the same API surface as the GenServer stores (StackStore,
  UserStore, SettingsStore) but persists to VeriSimDB via the octad API.

  Falls back gracefully when VeriSimDB is unreachable (the `VERISIMDB_URL`
  environment variable must be set, e.g. `http://localhost:8093`).
  """

  alias Stapeln.VeriSimDB.Client

  require Logger

  # ---------------------------------------------------------------------------
  # Availability check
  # ---------------------------------------------------------------------------

  @doc """
  Returns true when the VeriSimDB instance is reachable.

  This is the guard used by NativeBridge, Auth, and SettingsStore to decide
  whether to use VeriSimDB or fall back to GenServer stores.
  """
  @spec available?() :: boolean()
  def available? do
    case Client.health_check() do
      :ok -> true
      _ -> false
    end
  end

  # ---------------------------------------------------------------------------
  # Stack operations
  # ---------------------------------------------------------------------------

  @doc "List all stacks."
  @spec list_stacks() :: {:ok, [map()]}
  def list_stacks do
    case Client.list_octads("stacks") do
      {:ok, octads} ->
        stacks =
          octads
          |> Enum.map(&octad_to_stack/1)
          |> Enum.sort_by(& &1.id)

        {:ok, stacks}

      {:error, reason} ->
        Logger.warning("DbStore.list_stacks failed: #{inspect(reason)}")
        {:error, :db_error}
    end
  end

  @doc "Create a new stack from the given attributes map."
  @spec create_stack(map()) :: {:ok, map()} | {:error, term()}
  def create_stack(attrs) when is_map(attrs) do
    normalized = normalize_attrs(attrs)

    case Client.create_octad("stacks", normalized) do
      {:ok, octad} ->
        {:ok, octad_to_stack(octad)}

      {:error, reason} ->
        Logger.warning("DbStore.create_stack failed: #{inspect(reason)}")
        {:error, :db_error}
    end
  end

  @doc "Fetch a single stack by its VeriSimDB octad ID."
  @spec get_stack(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_stack(id) do
    case Client.get_octad(to_string(id)) do
      {:ok, octad} ->
        {:ok, octad_to_stack(octad)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, reason} ->
        Logger.warning("DbStore.get_stack failed: #{inspect(reason)}")
        {:error, :db_error}
    end
  end

  @doc "Update an existing stack."
  @spec update_stack(String.t(), map()) :: {:ok, map()} | {:error, :not_found | term()}
  def update_stack(id, attrs) when is_map(attrs) do
    normalized = normalize_attrs(attrs)

    case Client.update_octad(to_string(id), Map.put(normalized, :collection, "stacks")) do
      {:ok, octad} ->
        {:ok, octad_to_stack(octad)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, reason} ->
        Logger.warning("DbStore.update_stack failed: #{inspect(reason)}")
        {:error, :db_error}
    end
  end

  # ---------------------------------------------------------------------------
  # User operations
  # ---------------------------------------------------------------------------

  @doc "Create a user with the given email and password hash."
  @spec create_user(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def create_user(email, password_hash)
      when is_binary(email) and is_binary(password_hash) do
    attrs = %{email: email, password_hash: password_hash}

    case Client.create_octad("users", attrs) do
      {:ok, octad} ->
        octad_id = octad["id"] || octad["status"]["id"]
        {:ok, "user_#{octad_id}"}

      {:error, reason} ->
        Logger.warning("DbStore.create_user failed: #{inspect(reason)}")
        {:error, :db_error}
    end
  end

  @doc "Get a user by their string ID (e.g. `\"user_<octad-id>\"`)."
  @spec get_user(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_user(user_id) when is_binary(user_id) do
    case parse_user_id(user_id) do
      {:ok, octad_id} ->
        case Client.get_octad(octad_id) do
          {:ok, octad} ->
            {:ok, octad_to_user(octad)}

          {:error, :not_found} ->
            {:error, :not_found}

          {:error, reason} ->
            Logger.warning("DbStore.get_user failed: #{inspect(reason)}")
            {:error, :db_error}
        end

      :error ->
        {:error, :not_found}
    end
  end

  @doc "Get a user by email address."
  @spec get_user_by_email(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_user_by_email(email) when is_binary(email) do
    case Client.list_octads("users") do
      {:ok, octads} ->
        case Enum.find(octads, fn o ->
               get_in(o, ["metadata", "email"]) == email
             end) do
          nil -> {:error, :not_found}
          octad -> {:ok, octad_to_user(octad)}
        end

      {:error, reason} ->
        Logger.warning("DbStore.get_user_by_email failed: #{inspect(reason)}")
        {:error, :db_error}
    end
  end

  # ---------------------------------------------------------------------------
  # Settings operations
  # ---------------------------------------------------------------------------

  @doc """
  Get settings for a user. Returns the settings map (not wrapped in {:ok, ...}).

  When no user_id is given (global settings), returns the first settings
  octad or the default settings map.
  """
  @spec get_settings(String.t() | nil) :: map()
  def get_settings(nil) do
    case Client.list_octads("settings") do
      {:ok, [first | _]} ->
        stored = get_in(first, ["metadata", "settings"]) || %{}
        Map.merge(default_settings(), stored)

      _ ->
        default_settings()
    end
  end

  def get_settings(user_id) when is_binary(user_id) do
    case Client.list_octads("settings") do
      {:ok, octads} ->
        case Enum.find(octads, fn o ->
               get_in(o, ["metadata", "user_id"]) == user_id
             end) do
          nil ->
            default_settings()

          octad ->
            stored = get_in(octad, ["metadata", "settings"]) || %{}
            Map.merge(default_settings(), stored)
        end

      _ ->
        default_settings()
    end
  end

  @doc """
  Update settings for a user. Upserts the settings octad.

  When user_id is nil, operates on the first settings octad (global settings).
  """
  @spec update_settings(String.t() | nil, map()) :: {:ok, map()}
  def update_settings(nil, attrs) when is_map(attrs) do
    case Client.list_octads("settings") do
      {:ok, [first | _]} ->
        octad_id = first["id"] || get_in(first, ["status", "id"])
        existing = get_in(first, ["metadata", "settings"]) || %{}
        merged = Map.merge(existing, attrs)

        case Client.update_octad(octad_id, %{
               collection: "settings",
               settings: merged
             }) do
          {:ok, _} -> {:ok, Map.merge(default_settings(), merged)}
          {:error, _} -> {:ok, Map.merge(default_settings(), attrs)}
        end

      _ ->
        # No existing global settings — create one
        case Client.create_octad("settings", %{settings: attrs}) do
          {:ok, _} -> {:ok, Map.merge(default_settings(), attrs)}
          {:error, _} -> {:ok, Map.merge(default_settings(), attrs)}
        end
    end
  end

  def update_settings(user_id, attrs) when is_binary(user_id) and is_map(attrs) do
    case Client.list_octads("settings") do
      {:ok, octads} ->
        case Enum.find(octads, fn o ->
               get_in(o, ["metadata", "user_id"]) == user_id
             end) do
          nil ->
            # Create new settings for this user
            case Client.create_octad("settings", %{
                   user_id: user_id,
                   settings: attrs
                 }) do
              {:ok, _} -> {:ok, Map.merge(default_settings(), attrs)}
              {:error, _} -> {:ok, Map.merge(default_settings(), attrs)}
            end

          octad ->
            octad_id = octad["id"] || get_in(octad, ["status", "id"])
            existing = get_in(octad, ["metadata", "settings"]) || %{}
            merged = Map.merge(existing, attrs)

            case Client.update_octad(octad_id, %{
                   collection: "settings",
                   user_id: user_id,
                   settings: merged
                 }) do
              {:ok, _} -> {:ok, Map.merge(default_settings(), merged)}
              {:error, _} -> {:ok, Map.merge(default_settings(), attrs)}
            end
        end

      _ ->
        {:ok, Map.merge(default_settings(), attrs)}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp octad_to_stack(octad) do
    meta = octad["metadata"] || %{}
    status = octad["status"] || %{}

    %{
      id: octad["id"] || status["id"],
      name: meta["name"] || get_in(octad, ["document", "title"]) || "",
      description: meta["description"] || get_in(octad, ["document", "body"]) || "",
      services: meta["services"] || [],
      design: meta["design"],
      created_at: status["created_at"],
      updated_at: status["modified_at"]
    }
  end

  defp octad_to_user(octad) do
    meta = octad["metadata"] || %{}
    status = octad["status"] || %{}
    octad_id = octad["id"] || status["id"]

    %{
      id: "user_#{octad_id}",
      email: meta["email"] || "",
      password_hash: meta["password_hash"] || "",
      created_at: status["created_at"]
    }
  end

  defp normalize_attrs(attrs) do
    Map.new(attrs, fn
      {k, v} when is_atom(k) -> {k, v}
      {k, v} when is_binary(k) -> {safe_to_atom(k), v}
    end)
  rescue
    _error ->
      Map.new(attrs, fn
        {k, v} when is_atom(k) -> {k, v}
        {k, v} when is_binary(k) -> {safe_to_atom(k), v}
      end)
  end

  defp safe_to_atom(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> String.to_existing_atom(key)
  end

  defp parse_user_id("user_" <> rest), do: {:ok, rest}
  defp parse_user_id(_), do: :error

  defp default_settings do
    %{
      "theme" => "dark",
      "defaultRuntime" => "podman",
      "autoSave" => false,
      "backendUrl" => "/api"
    }
  end
end
