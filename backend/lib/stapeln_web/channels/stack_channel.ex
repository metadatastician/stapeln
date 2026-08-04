# SPDX-License-Identifier: MPL-2.0
# StackChannel - Real-time validation, security scanning, and gap analysis
#
# Clients join "stack:lobby" for general broadcasts or "stack:<id>" for
# stack-specific updates.  Three inbound events are supported:
#
#   "validate"      -> runs ValidationEngine, pushes "validation_result"
#   "security_scan" -> runs SecurityScanner,   pushes "security_result"
#   "gap_analysis"  -> runs GapAnalyzer,       pushes "gap_result"
#
# Each handler pushes results back to the caller only (not broadcast),
# keeping the interaction request/response-like while still benefiting
# from the persistent WebSocket connection.

defmodule StapelnWeb.StackChannel do
  use StapelnWeb, :channel

  @impl true
  def join("stack:lobby", _payload, socket) do
    {:ok, socket}
  end

  def join("stack:" <> _id, _payload, socket) do
    {:ok, socket}
  end

  # ---- Inbound events -------------------------------------------------------
  #
  # `stack_data` may be either a design document / legacy-services map, or
  # (the current wire format from App.res's WS call sites) that same JSON
  # re-encoded as a string value. Either way it is routed through
  # `Stapeln.Design.derive_services/1` to get the flattened services list the
  # engines expect — the legacy raw-services shape passes through unchanged.

  @impl true
  def handle_in("validate", %{"stack" => stack_data}, socket) do
    services = stack_data |> to_stack_map() |> Stapeln.Design.derive_services()
    report = Stapeln.ValidationEngine.validate(%{services: services})
    push(socket, "validation_result", %{data: report})
    {:noreply, socket}
  end

  @impl true
  def handle_in("security_scan", %{"stack" => stack_data}, socket) do
    services = stack_data |> to_stack_map() |> Stapeln.Design.derive_services()
    report = Stapeln.SecurityScanner.scan(%{services: services})
    push(socket, "security_result", %{data: report})
    {:noreply, socket}
  end

  @impl true
  def handle_in("gap_analysis", %{"stack" => stack_data}, socket) do
    services = stack_data |> to_stack_map() |> Stapeln.Design.derive_services()
    report = Stapeln.GapAnalyzer.analyze(%{services: services})
    push(socket, "gap_result", %{data: report})
    {:noreply, socket}
  end

  defp to_stack_map(stack_data) when is_map(stack_data), do: stack_data

  defp to_stack_map(stack_data) when is_binary(stack_data) do
    case Jason.decode(stack_data) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _other -> %{}
    end
  end

  defp to_stack_map(_other), do: %{}
end
