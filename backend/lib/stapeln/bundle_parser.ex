# SPDX-License-Identifier: MPL-2.0
# Stapeln.BundleParser - raises a deployment bundle back to the design it came from.

defmodule Stapeln.BundleParser do
  @moduledoc """
  The inverse of `Stapeln.BundleCodegen`: recovers a stack design from an
  emitted bundle.

  Lowering a design to files is only half a compiler. If the files cannot be
  read back, the canvas stops being the source of truth the moment anyone edits
  the output, and the two drift silently. `raise_design/1` closes that loop, and
  the round-trip property

      design == raise_design(generate(design))

  is what makes "the canvas is the source of truth" a checkable claim rather
  than an aspiration.

  ## What is and is not cross-validated

  `stapeln.design.json` is the authoritative carrier -- it holds the design
  document verbatim. The other eight files are *lowerings* of it and are not
  independently invertible, so this module cross-checks them rather than
  parsing them back.

  The check that is worth making is narrow, and deliberately so:

    * Every canvas component becomes exactly one service, named by the
      component's **id** (`Stapeln.Design.component_to_service/2`), in order.
      So `components[i].id == services[i].name` is a real invariant and is
      enforced.

    * `compose.toml` is **not** one-entry-per-component. The template carries a
      fixed three-service topology (the app, rokur, svalinn) and substitutes
      only `{{SERVICE_NAME}}` -- the first service's name. So the honest anchor
      is that `compose.toml` declares `[services.<first component id>]`, and
      that is what is asserted.

  Asserting "every component appears in compose.toml" would be false, and
  asserting something weaker that happens to hold vacuously would be worse than
  asserting nothing: a check that cannot fail is not a check.
  """

  alias Stapeln.BundleCodegen

  @design_file "stapeln.design.json"
  @compose_file "compose.toml"
  @schema "stapeln.design/v1"

  @doc """
  Recover the design document from `bundle`.

  Returns `{:ok, design}` where `design` is the value that was passed in as the
  stack's `:design`, or `{:error, reason}` if the bundle is incomplete, carries
  an unknown schema, or is internally inconsistent.
  """
  @spec raise_design(BundleCodegen.bundle()) :: {:ok, map() | nil} | {:error, String.t()}
  def raise_design(bundle) when is_map(bundle) do
    with :ok <- assert_complete(bundle),
         {:ok, doc} <- decode_design_file(bundle),
         :ok <- assert_schema(doc),
         :ok <- assert_services_match_components(doc),
         :ok <- assert_compose_anchors_primary(doc, bundle) do
      {:ok, doc["design"]}
    end
  end

  @doc """
  Recover the full `stapeln.design.json` document, not just its `design` key.

  Useful when the caller wants the derived services or the emission timestamp
  alongside the design itself.
  """
  @spec raise_document(BundleCodegen.bundle()) :: {:ok, map()} | {:error, String.t()}
  def raise_document(bundle) when is_map(bundle) do
    with :ok <- assert_complete(bundle),
         {:ok, doc} <- decode_design_file(bundle),
         :ok <- assert_schema(doc) do
      {:ok, doc}
    end
  end

  # ---------------------------------------------------------------------------

  defp assert_complete(bundle) do
    case BundleCodegen.bundle_files() -- Map.keys(bundle) do
      [] -> :ok
      missing -> {:error, "bundle is incomplete; missing: #{Enum.join(missing, ", ")}"}
    end
  end

  defp decode_design_file(bundle) do
    case Jason.decode(Map.fetch!(bundle, @design_file)) do
      {:ok, doc} when is_map(doc) ->
        {:ok, doc}

      {:ok, other} ->
        {:error, "#{@design_file} decoded to #{inspect(other)}, expected an object"}

      {:error, %Jason.DecodeError{} = e} ->
        {:error, "#{@design_file} is not valid JSON: #{Exception.message(e)}"}
    end
  end

  defp assert_schema(%{"schema" => @schema}), do: :ok

  defp assert_schema(%{"schema" => other}),
    do: {:error, "unknown design schema #{inspect(other)}; this parser understands #{@schema}"}

  defp assert_schema(_), do: {:error, "#{@design_file} has no schema field"}

  # Every canvas component becomes exactly one service, named by the component's
  # id, in order. A mismatch means the emitted services and the emitted design
  # disagree about what the stack contains -- which would make the bundle
  # self-contradictory even though every individual file looked fine.
  defp assert_services_match_components(doc) do
    ids = component_ids(doc)
    names = doc |> Map.get("services", []) |> Enum.map(&Map.get(&1, "name"))

    cond do
      # A design with no canvas (or a stack built from a plain services list)
      # has nothing to correspond, and that is legitimate.
      ids == :no_canvas -> :ok
      ids == names -> :ok
      true -> {:error, "design components #{inspect(ids)} do not match services #{inspect(names)}"}
    end
  end

  defp assert_compose_anchors_primary(doc, bundle) do
    case component_ids(doc) do
      :no_canvas ->
        :ok

      [] ->
        :ok

      [primary | _] ->
        compose = Map.fetch!(bundle, @compose_file)

        if String.contains?(compose, "[services.#{primary}]") do
          :ok
        else
          {:error,
           "#{@compose_file} does not declare [services.#{primary}] for the primary component"}
        end
    end
  end

  defp component_ids(doc) do
    case get_in(doc, ["design", "canvas", "components"]) do
      components when is_list(components) -> Enum.map(components, &Map.get(&1, "id"))
      _ -> :no_canvas
    end
  end
end
