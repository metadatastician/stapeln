# SPDX-License-Identifier: MPL-2.0
defmodule Stapeln.Parts do
  @moduledoc """
  The parts descriptor catalogue (rulings 12 and D1).

  A part without a groove manifest joins the stack through a descriptor. In v1
  the descriptors live here, one TOML file per known part in `priv/parts`; from
  v1.1 each part owns its descriptor in its own repo and this copy becomes a
  cache refreshed by PR. **The compiler never touches the network** -- every
  sha is pinned in the descriptor and read from disk.

  Descriptors are stapeln's own data files. They are not A2ML documents and not
  `.deed` documents.

  `load!/0` is strict in the same way rokur's loader is strict: a missing
  required field, a `sha` that is not 40 hex, a `slot` outside the table, a
  duplicate name, or an unknown key raises. An unknown key is an error rather
  than a warning because a descriptor is a pinning record -- silently ignoring
  a key the emitter does not understand is how a pin goes stale without anyone
  noticing.
  """

  alias Stapeln.Slots

  @top_keys ~w(part)
  @part_keys ~w(name slot interface model_component repo sha image build runtime contract)
  @required_part_keys ~w(name slot interface repo sha)
  @build_keys ~w(containerfile context)
  @runtime_keys ~w(ports mounts command env health)
  @contract_keys ~w(consumes manifest_url)
  @port_keys ~w(port protocol transaction)
  @health_keys ~w(path port)
  @interfaces ~w(oci groove)

  @sha_re ~r/\A[0-9a-f]{40}\z/

  @type t :: %{
          name: String.t(),
          slot: String.t(),
          interface: String.t(),
          model_component: String.t(),
          repo: String.t(),
          sha: String.t(),
          image: String.t(),
          build: %{containerfile: String.t(), context: String.t()},
          ports: [%{port: pos_integer(), protocol: String.t(), transaction: String.t()}],
          mounts: [String.t()],
          command: [String.t()],
          env: [String.t()],
          health: %{path: String.t(), port: pos_integer()} | nil,
          consumes: [String.t()],
          manifest_url: String.t()
        }

  @doc """
  Every descriptor in `priv/parts`, keyed by part name. Raises on any invalid
  descriptor -- there is no partial catalogue, because a partial catalogue
  emits a bundle that silently omits a part.
  """
  @spec load!() :: %{optional(String.t()) => t()}
  def load!(dir \\ descriptor_dir()) do
    dir
    |> descriptor_paths()
    |> Enum.map(&load_file!/1)
    |> Enum.reduce(%{}, fn part, acc ->
      if Map.has_key?(acc, part.name) do
        raise ArgumentError, "duplicate part descriptor name #{inspect(part.name)}"
      end

      Map.put(acc, part.name, part)
    end)
  end

  @doc "The directory the catalogue is read from."
  @spec descriptor_dir() :: String.t()
  def descriptor_dir, do: Application.app_dir(:stapeln, "priv/parts")

  defp descriptor_paths(dir) do
    case File.ls(dir) do
      {:ok, entries} ->
        entries
        |> Enum.filter(&String.ends_with?(&1, ".toml"))
        |> Enum.sort()
        |> Enum.map(&Path.join(dir, &1))

      {:error, reason} ->
        raise ArgumentError,
              "cannot read parts descriptor directory #{inspect(dir)}: #{inspect(reason)}"
    end
  end

  defp load_file!(path) do
    doc =
      case Toml.decode_file(path) do
        {:ok, doc} -> doc
        {:error, reason} -> raise ArgumentError, "#{path}: not valid TOML: #{inspect(reason)}"
      end

    reject_unknown!(path, doc, @top_keys, "document")

    part =
      case Map.fetch(doc, "part") do
        {:ok, part} when is_map(part) -> part
        _ -> raise ArgumentError, "#{path}: missing the [part] table"
      end

    reject_unknown!(path, part, @part_keys, "[part]")

    Enum.each(@required_part_keys, fn key ->
      case Map.get(part, key) do
        value when is_binary(value) and value != "" -> :ok
        _ -> raise ArgumentError, "#{path}: [part] #{key} is required and must be a non-empty string"
      end
    end)

    name = Map.fetch!(part, "name")
    slot = Map.fetch!(part, "slot")
    interface = Map.fetch!(part, "interface")
    sha = Map.fetch!(part, "sha")

    unless Slots.slot?(slot) do
      raise ArgumentError,
            "#{path}: slot #{inspect(slot)} is not in the slot table (#{Enum.join(Slots.ids(), ", ")})"
    end

    unless interface in @interfaces do
      raise ArgumentError,
            "#{path}: interface #{inspect(interface)} must be one of #{Enum.join(@interfaces, ", ")}"
    end

    unless Regex.match?(@sha_re, sha) do
      raise ArgumentError, "#{path}: sha must be 40 lowercase hex characters, got #{inspect(sha)}"
    end

    build = sub_table!(path, part, "build", @build_keys)
    runtime = sub_table!(path, part, "runtime", @runtime_keys)
    contract = sub_table!(path, part, "contract", @contract_keys)

    %{
      name: name,
      slot: slot,
      interface: interface,
      model_component: string_field(part, "model_component"),
      repo: Map.fetch!(part, "repo"),
      sha: sha,
      image: string_field(part, "image"),
      build: %{
        containerfile: string_field(build, "containerfile", "Containerfile"),
        context: string_field(build, "context", ".")
      },
      ports: ports!(path, Map.get(runtime, "ports", [])),
      mounts: string_list!(path, "runtime.mounts", Map.get(runtime, "mounts", [])),
      command: string_list!(path, "runtime.command", Map.get(runtime, "command", [])),
      env: string_list!(path, "runtime.env", Map.get(runtime, "env", [])),
      health: health!(path, Map.get(runtime, "health")),
      consumes: string_list!(path, "contract.consumes", Map.get(contract, "consumes", [])),
      manifest_url: string_field(contract, "manifest_url")
    }
  end

  defp sub_table!(path, part, key, allowed) do
    case Map.get(part, key, %{}) do
      table when is_map(table) ->
        reject_unknown!(path, table, allowed, "[part.#{key}]")
        table

      other ->
        raise ArgumentError, "#{path}: [part.#{key}] must be a table, got #{inspect(other)}"
    end
  end

  defp reject_unknown!(path, map, allowed, where) do
    case Map.keys(map) -- allowed do
      [] -> :ok
      unknown -> raise ArgumentError, "#{path}: unknown key(s) in #{where}: #{Enum.join(Enum.sort(unknown), ", ")}"
    end
  end

  defp string_field(map, key, default \\ "") do
    case Map.get(map, key, default) do
      value when is_binary(value) -> value
      other -> raise ArgumentError, "#{key} must be a string, got #{inspect(other)}"
    end
  end

  defp string_list!(path, where, list) when is_list(list) do
    Enum.each(list, fn
      value when is_binary(value) -> :ok
      other -> raise ArgumentError, "#{path}: #{where} must be a list of strings, got #{inspect(other)}"
    end)

    list
  end

  defp string_list!(path, where, other) do
    raise ArgumentError, "#{path}: #{where} must be a list of strings, got #{inspect(other)}"
  end

  defp ports!(path, ports) when is_list(ports) do
    Enum.map(ports, fn
      port when is_map(port) ->
        reject_unknown!(path, port, @port_keys, "a runtime.ports entry")

        number = Map.get(port, "port")

        unless is_integer(number) and number >= 1 and number <= 65_535 do
          raise ArgumentError, "#{path}: runtime.ports port must be 1..65535, got #{inspect(number)}"
        end

        # Network doctrine of 2026-09-02: every port carries the protocol and
        # the transaction it serves, and the descriptor is the single place the
        # number lives.
        %{
          port: number,
          protocol: string_field(port, "protocol", "tcp"),
          transaction: string_field(port, "transaction")
        }

      other ->
        raise ArgumentError, "#{path}: runtime.ports entries must be inline tables, got #{inspect(other)}"
    end)
  end

  defp ports!(path, other) do
    raise ArgumentError, "#{path}: runtime.ports must be a list, got #{inspect(other)}"
  end

  defp health!(_path, nil), do: nil

  defp health!(path, health) when is_map(health) do
    reject_unknown!(path, health, @health_keys, "runtime.health")

    port = Map.get(health, "port")

    unless is_integer(port) and port >= 1 and port <= 65_535 do
      raise ArgumentError, "#{path}: runtime.health port must be 1..65535, got #{inspect(port)}"
    end

    %{path: string_field(health, "path", "/health"), port: port}
  end

  defp health!(path, other) do
    raise ArgumentError, "#{path}: runtime.health must be an inline table, got #{inspect(other)}"
  end
end
