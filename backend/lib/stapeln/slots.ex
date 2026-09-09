# SPDX-License-Identifier: MPL-2.0
defmodule Stapeln.Slots do
  @moduledoc """
  The slot table (ruling 5) and the designer mapping.

  A slot is the role a part plays in a stack. v1 does not change `Model.res`:
  the slot of a placed component is derived here, by a fixed mapping from the
  component type the canvas already carries. `UnknownType` -- anything not in
  the table -- maps to `custom`. The `slot` field on the model itself is v1.1.

  ## Why `keys/0` has twelve entries and `ids/0` has thirteen

  The slot table lists thirteen ids, but the `[slots]` table of `stack.lock`
  carries twelve keys. `custom` is excluded deliberately: `[slots]` maps one
  slot to one part name, and `custom` is the one slot that can hold many parts
  at once (any OCI image the user drags in), so it cannot be a single-valued
  key. It remains available as a *part's* slot -- a custom part appears in
  `[[part]]` with `slot = "custom"` -- it just has no row in `[slots]`.
  """

  @custom "custom"

  # Slot id => the `Model.res` componentType values that land in it today.
  @table [
    {"runtime", ["Podman", "Docker", "Nerdctl"]},
    {"base-image", ["LagoGrey"]},
    {"secrets-gate", ["Rokur"]},
    {"edge-gateway", ["Svalinn"]},
    {"seam-sealant", ["Selur"]},
    {"orchestration-verification", ["Vordr"]},
    {"packer-signer", ["CerroTorre"]},
    # No componentType maps here in v1; the slot exists so a design can record
    # the part as missing rather than as absent from the vocabulary.
    {"advisory-validator", []},
    {"firewall", []},
    {"deploy-target", []},
    {"storage", ["Volume"]},
    {"network", ["Network"]}
  ]

  @keys Enum.map(@table, &elem(&1, 0))
  @ids @keys ++ [@custom]

  @by_component Enum.flat_map(@table, fn {slot, components} ->
                  Enum.map(components, &{&1, slot})
                end)
                |> Map.new()

  @doc "Every slot id, including `custom`. Thirteen."
  @spec ids() :: [String.t()]
  def ids, do: @ids

  @doc "The slot ids that get a key in `stack.lock`'s `[slots]` table. Twelve."
  @spec keys() :: [String.t()]
  def keys, do: @keys

  @doc "The `custom` slot id."
  @spec custom() :: String.t()
  def custom, do: @custom

  @doc "True when `id` is a slot in the table."
  @spec slot?(term()) :: boolean()
  def slot?(id) when is_binary(id), do: id in @ids
  def slot?(_), do: false

  @doc """
  The slot a placed component belongs to. Anything outside the table -- which
  is what `UnknownType(string)` reaches us as -- is `custom`.
  """
  @spec of_component(term()) :: String.t()
  def of_component(component) when is_binary(component) do
    Map.get(@by_component, component, @custom)
  end

  def of_component(_non_binary), do: @custom
end
