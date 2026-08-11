# SPDX-License-Identifier: MPL-2.0
defmodule Stapeln.Design do
  @moduledoc """
  Design-document validation and service derivation.

  A "design" is the full-fidelity JSON document produced by the frontend's
  `DesignFormat.serializeDesign` (see `frontend/src/DesignFormat.res`):

      %{
        "version" => "1.0",
        "metadata" => %{
          "created" => "...",
          "author" => "...",
          "description" => "..."
        },
        "canvas" => %{
          "components" => [
            %{
              "id" => "web-1",
              "type" => "Podman",
              "position" => %{"x" => 0.0, "y" => 0.0},
              "config" => %{"port" => "8080"}
            },
            ...
          ],
          "connections" => [
            %{"id" => "conn-1", "from" => "web-1", "to" => "db-1"},
            ...
          ]
        }
      }

  This is stored verbatim (opaquely) as the stack's `design` field so the
  editor can round-trip position/config/connections without loss. Analyzers
  (SecurityScanner, GapAnalyzer, ValidationEngine) and Codegen never see the
  design document itself — they consume the flattened `services` list that
  `derive_services/1` produces from it.

  Connection direction: a connection `%{"from" => a, "to" => b}` means
  component `a` depends on component `b` (mirrors docker-compose
  `depends_on` semantics — the edge points at the dependency), so `a`'s
  derived service gets `"depends_on" => [b, ...]`.

  For backward compatibility, both functions also accept the legacy shape —
  a plain map with a top-level `"services"` list (as previously emitted by
  `App.res`'s hand-rolled `serializeStack`) — and pass it through unchanged.
  """

  @doc """
  Shape-check a decoded JSON map: either a design document (has `"version"`,
  `"metadata"`, and a `"canvas"` with list-valued `"components"` and
  `"connections"`) or a legacy stack shape (top-level `"services"` list).
  """
  @spec valid?(map()) :: :ok | {:error, String.t()}
  def valid?(%{"version" => _version, "metadata" => metadata, "canvas" => canvas})
      when is_map(metadata) and is_map(canvas) do
    components = Map.get(canvas, "components")
    connections = Map.get(canvas, "connections")

    if is_list(components) and is_list(connections) do
      :ok
    else
      {:error, "canvas.components and canvas.connections must both be lists"}
    end
  end

  def valid?(%{"version" => _, "metadata" => _}) do
    {:error, "design document missing canvas"}
  end

  def valid?(%{"services" => services}) when is_list(services), do: :ok

  def valid?(_other), do: {:error, "not a recognised design document or legacy stack shape"}

  @doc """
  Flatten a design document's canvas into the legacy `services` list shape
  consumed by the analyzers and Codegen. Each canvas component becomes
  `%{"name" => id, "kind" => type, "port" => port}`, with `"depends_on"`
  added when the component is the source (`"from"`) of one or more
  connections.

  Accepts the legacy shape (top-level `"services"` list) unchanged, for
  WS/API back-compat with callers that never adopted the design-doc format.
  """
  @spec derive_services(map()) :: [map()]
  def derive_services(%{"canvas" => canvas}) when is_map(canvas) do
    components = Map.get(canvas, "components")
    connections = Map.get(canvas, "connections")

    if is_list(components) do
      depends_on_by_id = depends_on_index(connections)

      Enum.map(components, fn component ->
        component_to_service(component, depends_on_by_id)
      end)
    else
      []
    end
  end

  def derive_services(%{"services" => services}) when is_list(services), do: services

  def derive_services(_other), do: []

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp component_to_service(component, depends_on_by_id) when is_map(component) do
    id = Map.get(component, "id", "")

    base = %{
      "name" => id,
      "kind" => Map.get(component, "type", "unknown"),
      "port" => derive_port(component)
    }

    case Map.get(depends_on_by_id, id) do
      nil -> base
      [] -> base
      depends_on -> Map.put(base, "depends_on", depends_on)
    end
  end

  defp component_to_service(_non_map, _depends_on_by_id) do
    %{"name" => "unnamed-service", "kind" => "unknown", "port" => 0}
  end

  defp depends_on_index(connections) when is_list(connections) do
    Enum.reduce(connections, %{}, fn connection, acc ->
      with %{} <- connection,
           from when is_binary(from) <- Map.get(connection, "from"),
           to when is_binary(to) <- Map.get(connection, "to") do
        Map.update(acc, from, [to], fn existing -> existing ++ [to] end)
      else
        _ -> acc
      end
    end)
  end

  defp depends_on_index(_other), do: %{}

  defp derive_port(component) do
    component
    |> Map.get("config")
    |> extract_port()
    |> parse_port()
  end

  defp extract_port(config) when is_map(config), do: Map.get(config, "port")
  defp extract_port(_other), do: nil

  defp parse_port(nil), do: 0
  defp parse_port(port) when is_integer(port), do: port

  defp parse_port(port) when is_binary(port) do
    case Integer.parse(port) do
      {value, _rest} -> value
      :error -> 0
    end
  end

  defp parse_port(_other), do: 0
end
