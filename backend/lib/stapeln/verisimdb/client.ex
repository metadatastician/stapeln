# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)

defmodule Stapeln.VeriSimDB.Client do
  @moduledoc """
  HTTP client for communicating with a remote VeriSimDB instance.

  Connects when the `VERISIMDB_URL` environment variable is set (e.g.
  `http://localhost:9420`).  All writes and queries go through the VeriSimDB
  REST API.  When the URL is not configured or the instance is unreachable,
  every function returns `{:error, reason}` so the caller can fall back to
  local storage.
  """

  @write_path "/audit"
  @query_path "/audit"
  @default_connect_timeout 5_000
  @default_receive_timeout 10_000

  @doc """
  Return the configured connect timeout in milliseconds.

  Reads from application config `:stapeln, :verisimdb_connect_timeout`,
  falling back to #{@default_connect_timeout} ms.
  """
  @spec connect_timeout() :: pos_integer()
  def connect_timeout do
    Application.get_env(:stapeln, :verisimdb_connect_timeout, @default_connect_timeout)
  end

  @doc """
  Return the configured receive timeout in milliseconds.

  Reads from application config `:stapeln, :verisimdb_receive_timeout`,
  falling back to #{@default_receive_timeout} ms.
  """
  @spec receive_timeout() :: pos_integer()
  def receive_timeout do
    Application.get_env(:stapeln, :verisimdb_receive_timeout, @default_receive_timeout)
  end

  @doc """
  Perform a lightweight health check against the remote VeriSimDB instance.

  Returns `:ok` when the instance is reachable, or `{:error, reason}`
  when the URL is not configured or the instance does not respond.
  """
  @spec health_check() :: :ok | {:error, term()}
  def health_check do
    with {:ok, base_url} <- verisimdb_url() do
      case get(base_url <> "/health") do
        {:ok, %{status: status}} when status in 200..299 -> :ok
        {:ok, %{status: status}} -> {:error, {:verisimdb_status, status}}
        {:error, reason} -> {:error, {:verisimdb_request, reason}}
      end
    end
  end

  @doc """
  Write an audit entry to the remote VeriSimDB instance.

  Returns `:ok` on success or `{:error, reason}` if the instance is
  unconfigured or unreachable.
  """
  @spec write(map()) :: :ok | {:error, term()}
  def write(entry) when is_map(entry) do
    with {:ok, base_url} <- verisimdb_url(),
         url <- base_url <> @write_path,
         {:ok, body} <- encode(entry) do
      case post(url, body) do
        {:ok, %{status: status}} when status in 200..299 ->
          :ok

        {:ok, %{status: status}} ->
          {:error, {:verisimdb_status, status}}

        {:error, reason} ->
          {:error, {:verisimdb_request, reason}}
      end
    end
  end

  @doc """
  Query audit entries from the remote VeriSimDB instance.

  Supported `opts`:
  - `:event_type` — atom, filter by event type
  - `:since`      — ISO 8601 string
  - `:until`      — ISO 8601 string
  - `:limit`      — integer, max results

  Returns `{:ok, [map()]}` on success or `{:error, reason}`.
  """
  @spec query(keyword()) :: {:ok, [map()]} | {:error, term()}
  def query(opts \\ []) do
    with {:ok, base_url} <- verisimdb_url(),
         url <- base_url <> @query_path <> query_string(opts) do
      case get(url) do
        {:ok, %{status: status, body: body}} when status in 200..299 ->
          decode_entries(body)

        {:ok, %{status: status}} ->
          {:error, {:verisimdb_status, status}}

        {:error, reason} ->
          {:error, {:verisimdb_request, reason}}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Generic Octad CRUD (for data storage, not just audit)
  # ---------------------------------------------------------------------------

  @octad_path "/octads"

  @doc """
  Create a new octad entity.

  The `attrs` map is stored in the `metadata` field of the octad. The
  `collection` string (e.g. "stacks", "users") is recorded in both
  `metadata.collection` and `types` for filtering.

  Returns `{:ok, octad_map}` on success or `{:error, reason}`.
  """
  @spec create_octad(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def create_octad(collection, attrs) when is_binary(collection) and is_map(attrs) do
    payload = %{
      "title" => Map.get(attrs, :name, Map.get(attrs, :email, collection)),
      "types" => ["stapeln:#{collection}"],
      "metadata" => Map.put(attrs, :collection, collection),
      "provenance" => %{
        "event_type" => "created",
        "actor" => "stapeln",
        "source" => "stapeln-backend"
      }
    }

    with {:ok, base_url} <- verisimdb_url(),
         {:ok, body} <- encode(payload) do
      case post(base_url <> @octad_path, body) do
        {:ok, %{status: status, body: resp_body}} when status in 200..299 ->
          decode_octad(resp_body)

        {:ok, %{status: status}} ->
          {:error, {:verisimdb_status, status}}

        {:error, reason} ->
          {:error, {:verisimdb_request, reason}}
      end
    end
  end

  @doc """
  Retrieve a single octad by its ID.

  Returns `{:ok, octad_map}` or `{:error, :not_found}`.
  """
  @spec get_octad(String.t()) :: {:ok, map()} | {:error, :not_found | term()}
  def get_octad(id) when is_binary(id) do
    with {:ok, base_url} <- verisimdb_url() do
      case get(base_url <> @octad_path <> "/" <> URI.encode(id)) do
        {:ok, %{status: 200, body: body}} ->
          decode_octad(body)

        {:ok, %{status: 404}} ->
          {:error, :not_found}

        {:ok, %{status: status}} ->
          {:error, {:verisimdb_status, status}}

        {:error, reason} ->
          {:error, {:verisimdb_request, reason}}
      end
    end
  end

  @doc """
  Update an existing octad. Only the provided fields in `attrs` are merged
  into the existing metadata.
  """
  @spec update_octad(String.t(), map()) :: {:ok, map()} | {:error, :not_found | term()}
  def update_octad(id, attrs) when is_binary(id) and is_map(attrs) do
    payload = %{
      "title" => Map.get(attrs, :name, Map.get(attrs, :email, nil)),
      "metadata" => attrs,
      "provenance" => %{
        "event_type" => "modified",
        "actor" => "stapeln",
        "source" => "stapeln-backend"
      }
    }

    with {:ok, base_url} <- verisimdb_url(),
         {:ok, body} <- encode(payload) do
      case put(base_url <> @octad_path <> "/" <> URI.encode(id), body) do
        {:ok, %{status: status, body: resp_body}} when status in 200..299 ->
          decode_octad(resp_body)

        {:ok, %{status: 404}} ->
          {:error, :not_found}

        {:ok, %{status: status}} ->
          {:error, {:verisimdb_status, status}}

        {:error, reason} ->
          {:error, {:verisimdb_request, reason}}
      end
    end
  end

  @doc """
  Delete an octad by ID.
  """
  @spec delete_octad(String.t()) :: :ok | {:error, :not_found | term()}
  def delete_octad(id) when is_binary(id) do
    with {:ok, base_url} <- verisimdb_url() do
      case delete(base_url <> @octad_path <> "/" <> URI.encode(id)) do
        {:ok, %{status: 204}} -> :ok
        {:ok, %{status: 404}} -> {:error, :not_found}
        {:ok, %{status: status}} -> {:error, {:verisimdb_status, status}}
        {:error, reason} -> {:error, {:verisimdb_request, reason}}
      end
    end
  end

  @doc """
  List all octads, optionally filtered client-side by collection name.

  Returns `{:ok, [map()]}`.
  """
  @spec list_octads(String.t() | nil) :: {:ok, [map()]} | {:error, term()}
  def list_octads(collection \\ nil) do
    with {:ok, base_url} <- verisimdb_url() do
      case get(base_url <> @octad_path <> "?limit=10000") do
        {:ok, %{status: 200, body: body}} ->
          {:ok, octads} = decode_octad_list(body)

          filtered =
            if collection do
              Enum.filter(octads, fn o ->
                get_in(o, ["metadata", "collection"]) == collection
              end)
            else
              octads
            end

          {:ok, filtered}

        {:ok, %{status: status}} ->
          {:error, {:verisimdb_status, status}}

        {:error, reason} ->
          {:error, {:verisimdb_request, reason}}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # HTTP Helpers (uses Req, already a project dependency)
  # ---------------------------------------------------------------------------

  defp post(url, body) do
    Req.post(url,
      body: body,
      headers: [{"content-type", "application/json"}, {"accept", "application/json"}],
      connect_options: [timeout: connect_timeout()],
      receive_timeout: receive_timeout()
    )
  rescue
    error -> {:error, {:http_error, error}}
  end

  defp get(url) do
    Req.get(url,
      headers: [{"accept", "application/json"}],
      connect_options: [timeout: connect_timeout()],
      receive_timeout: receive_timeout()
    )
  rescue
    error -> {:error, {:http_error, error}}
  end

  defp put(url, body) do
    Req.put(url,
      body: body,
      headers: [{"content-type", "application/json"}, {"accept", "application/json"}],
      connect_options: [timeout: connect_timeout()],
      receive_timeout: receive_timeout()
    )
  rescue
    error -> {:error, {:http_error, error}}
  end

  defp delete(url) do
    Req.delete(url,
      headers: [{"accept", "application/json"}],
      connect_options: [timeout: connect_timeout()],
      receive_timeout: receive_timeout()
    )
  rescue
    error -> {:error, {:http_error, error}}
  end

  # ---------------------------------------------------------------------------
  # Encoding / Decoding
  # ---------------------------------------------------------------------------

  defp encode(entry) do
    case Jason.encode(entry) do
      {:ok, _json} = ok -> ok
      {:error, reason} -> {:error, {:encode_error, reason}}
    end
  end

  defp decode_octad(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, octad} when is_map(octad) -> {:ok, octad}
      {:ok, _other} -> {:error, :invalid_response}
      {:error, reason} -> {:error, {:decode_error, reason}}
    end
  end

  defp decode_octad(body) when is_map(body), do: {:ok, body}
  defp decode_octad(_), do: {:error, :invalid_response}

  defp decode_octad_list(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, list} when is_list(list) -> {:ok, list}
      {:ok, %{"data" => list}} when is_list(list) -> {:ok, list}
      {:ok, _other} -> {:ok, []}
      {:error, reason} -> {:error, {:decode_error, reason}}
    end
  end

  defp decode_octad_list(body) when is_list(body), do: {:ok, body}
  defp decode_octad_list(body) when is_map(body), do: {:ok, Map.get(body, "data", [])}
  defp decode_octad_list(_), do: {:ok, []}

  defp decode_entries(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"data" => entries}} when is_list(entries) -> {:ok, entries}
      {:ok, entries} when is_list(entries) -> {:ok, entries}
      {:ok, _other} -> {:ok, []}
      {:error, reason} -> {:error, {:decode_error, reason}}
    end
  end

  defp decode_entries(body) when is_list(body), do: {:ok, body}
  defp decode_entries(body) when is_map(body), do: {:ok, Map.get(body, "data", [])}
  defp decode_entries(_), do: {:ok, []}

  # ---------------------------------------------------------------------------
  # Configuration
  # ---------------------------------------------------------------------------

  defp verisimdb_url do
    case System.get_env("VERISIMDB_URL") do
      nil -> {:error, :verisimdb_not_configured}
      "" -> {:error, :verisimdb_not_configured}
      url -> {:ok, String.trim_trailing(url, "/")}
    end
  end

  defp query_string(opts) do
    params =
      []
      |> maybe_add("event_type", Keyword.get(opts, :event_type), &Atom.to_string/1)
      |> maybe_add("since", Keyword.get(opts, :since), & &1)
      |> maybe_add("until", Keyword.get(opts, :until), & &1)
      |> maybe_add("limit", Keyword.get(opts, :limit), &Integer.to_string/1)

    case params do
      [] -> ""
      pairs -> "?" <> Enum.join(pairs, "&")
    end
  end

  defp maybe_add(acc, _key, nil, _transform), do: acc

  defp maybe_add(acc, key, value, transform) do
    acc ++ ["#{key}=#{URI.encode_www_form(transform.(value))}"]
  end
end
