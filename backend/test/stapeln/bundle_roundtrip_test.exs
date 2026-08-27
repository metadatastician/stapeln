# SPDX-License-Identifier: MPL-2.0

defmodule Stapeln.BundleRoundtripTest do
  use ExUnit.Case, async: true

  alias Stapeln.{BundleCodegen, BundleParser, Design}

  @meta [author: "A. Author", email: "a@example.org", license: "MPL-2.0", owner: "acme"]

  # Every componentType the designer can produce, as the string that actually
  # travels on the wire. These are DISPLAY names, not variant names, and they
  # are irregular on purpose:
  #
  #   * "Cerro Torre" and "Lago Grey" contain a SPACE
  #   * "selur" and "nerdctl" are lowercase
  #   * "Vörðr" is NOT ASCII -- it carries U+00F6 and U+00F0
  #
  # Enumerated exhaustively rather than sampled. The domain is finite and small,
  # so a table covers it completely and deterministically; property-based
  # generation would only sample it, and would be free to never generate the one
  # value most likely to break -- the non-ASCII one.
  #
  # Source of truth: Model.res:227 (encode) and DesignFormat.res:84 (decode).
  @component_types [
    "Cerro Torre",
    "Lago Grey",
    "Svalinn",
    "selur",
    "Vörðr",
    "Podman",
    "Docker",
    "nerdctl",
    "Volume",
    "Network",
    # Not yet in Model.res -- the frontend variant lands separately. Included
    # here because the backend treats component types as opaque strings, so this
    # asserts the backend is ready for it, NOT that the designer can emit it.
    "Rokur"
  ]

  # Mirrors StackController.build_attrs/1's "canvas" clause, which is the only
  # path that produces a stored design. Building the fixture any other way would
  # prove losslessness over a shape the application never creates.
  defp stack_from(design_doc, name \\ "roundtrip-stack") do
    %{
      name: name,
      description: get_in(design_doc, ["metadata", "description"]),
      design: design_doc,
      services: Design.derive_services(design_doc)
    }
  end

  defp design_doc(components, connections \\ []) do
    %{
      "version" => "1.0",
      "metadata" => %{
        "created" => "2026-08-27T00:00:00.000Z",
        "author" => "Jonathan D.A. Jewell",
        "description" => "round-trip fixture"
      },
      "canvas" => %{"components" => components, "connections" => connections}
    }
  end

  defp component(id, type, x \\ 0.0, y \\ 0.0, config \\ %{}) do
    %{"id" => id, "type" => type, "position" => %{"x" => x, "y" => y}, "config" => config}
  end

  defp lower_then_raise(stack) do
    {:ok, bundle} = BundleCodegen.generate(stack, @meta)
    {:ok, design} = BundleParser.raise_design(bundle)
    design
  end

  describe "the round-trip property: design == raise(lower(design))" do
    test "holds for every component type, one at a time" do
      for type <- @component_types do
        doc = design_doc([component("c-1", type, 10.0, 20.0, %{"port" => "8080"})])

        assert lower_then_raise(stack_from(doc)) == doc,
               "round-trip lost or altered the design for component type #{inspect(type)}"
      end
    end

    test "holds for a design containing all eleven types at once" do
      components =
        @component_types
        |> Enum.with_index()
        |> Enum.map(fn {type, i} -> component("c-#{i}", type, i * 40.0, 0.0) end)

      doc = design_doc(components)

      assert lower_then_raise(stack_from(doc)) == doc
    end

    test "preserves the non-ASCII type byte-for-byte" do
      # Vörðr is the one that a stray latin-1 round-trip, a naive downcase, or a
      # slug-ifying "clean-up" would silently mangle. Compare codepoints, not
      # just equality of the whole map, so a failure says WHAT changed.
      doc = design_doc([component("v-1", "Vörðr")])

      recovered = lower_then_raise(stack_from(doc))
      [got] = get_in(recovered, ["canvas", "components"])

      assert got["type"] == "Vörðr"
      assert String.to_charlist(got["type"]) == ~c"Vörðr"
      assert byte_size(got["type"]) == 7, "expected 5 codepoints in 7 bytes (ö and ð are 2 each)"
    end

    test "preserves float positions, connections and nested config" do
      doc =
        design_doc(
          [
            component("web-1", "Podman", 12.5, 34.0, %{"port" => "8080", "nested" => %{"a" => [1, 2]}}),
            component("db-1", "Volume", 220.0, 34.0)
          ],
          [%{"id" => "conn-1", "from" => "web-1", "to" => "db-1"}]
        )

      recovered = lower_then_raise(stack_from(doc))

      assert recovered == doc
      # Compare decoded terms, not strings: 12.5 must come back as a float, not
      # as "12.5", and not rounded to 13.
      [web, _db] = get_in(recovered, ["canvas", "components"])
      assert web["position"]["x"] === 12.5
      assert web["config"]["nested"]["a"] == [1, 2]
    end

    test "a design with no canvas still round-trips (nil is a legitimate design)" do
      stack = %{name: "plain", design: nil, services: [%{"name" => "web"}]}

      {:ok, bundle} = BundleCodegen.generate(stack, @meta)
      assert {:ok, nil} = BundleParser.raise_design(bundle)
    end
  end

  describe "the derived-services invariant" do
    test "components map one-to-one and in order onto services, keyed by id" do
      doc =
        design_doc([
          component("alpha", "Podman"),
          component("beta", "Volume"),
          component("gamma", "Network")
        ])

      {:ok, document} = BundleCodegen.generate(stack_from(doc), @meta)
      {:ok, raised} = BundleParser.raise_document(document)

      assert Enum.map(raised["services"], & &1["name"]) == ~w(alpha beta gamma)
      # kind carries the TYPE, name carries the ID. Getting these the wrong way
      # round would still "work" for single-component designs.
      assert Enum.map(raised["services"], & &1["kind"]) == ["Podman", "Volume", "Network"]
    end

    test "compose.toml anchors on the primary component's id" do
      doc = design_doc([component("frontdoor", "Svalinn"), component("store", "Volume")])
      {:ok, bundle} = BundleCodegen.generate(stack_from(doc), @meta)

      assert bundle["compose.toml"] =~ "[services.frontdoor]"
      # compose.toml is NOT one-entry-per-component: the template carries a fixed
      # app/rokur/svalinn topology and substitutes only the primary name. Pinning
      # that here so nobody later "fixes" the parser to demand all of them.
      refute bundle["compose.toml"] =~ "[services.store]"
    end
  end

  describe "the gate can actually fail" do
    # A round-trip test that only ever sees well-formed input proves nothing.
    # Each of these tampers with one thing and asserts the parser REJECTS it.

    setup do
      doc = design_doc([component("web-1", "Podman")])
      {:ok, bundle} = BundleCodegen.generate(stack_from(doc), @meta)
      {:ok, bundle: bundle, doc: doc}
    end

    test "rejects an incomplete bundle", %{bundle: bundle} do
      assert {:error, reason} = BundleParser.raise_design(Map.delete(bundle, "compose.toml"))
      assert reason =~ "incomplete"
      assert reason =~ "compose.toml"
    end

    test "rejects an unknown schema", %{bundle: bundle} do
      tampered = swap_design(bundle, &Map.put(&1, "schema", "stapeln.design/v99"))

      assert {:error, reason} = BundleParser.raise_design(tampered)
      assert reason =~ "unknown design schema"
    end

    test "rejects malformed JSON", %{bundle: bundle} do
      tampered = Map.put(bundle, "stapeln.design.json", "{not json")

      assert {:error, reason} = BundleParser.raise_design(tampered)
      assert reason =~ "not valid JSON"
    end

    test "rejects a bundle whose services disagree with its design", %{bundle: bundle} do
      # The single most valuable check here: every file individually looks fine,
      # but the bundle contradicts itself about what the stack contains.
      tampered = swap_design(bundle, &Map.put(&1, "services", [%{"name" => "something-else"}]))

      assert {:error, reason} = BundleParser.raise_design(tampered)
      assert reason =~ "do not match services"
    end

    test "rejects a compose.toml that does not declare the primary service", %{bundle: bundle} do
      tampered = Map.put(bundle, "compose.toml", "version = \"1.0\"\n[services.wrong]\n")

      assert {:error, reason} = BundleParser.raise_design(tampered)
      assert reason =~ "does not declare [services.web-1]"
    end

    test "an untampered bundle passes all of the above", %{bundle: bundle, doc: doc} do
      # The control. Without it, every test in this block could be passing
      # because raise_design/1 rejects everything.
      assert {:ok, ^doc} = BundleParser.raise_design(bundle)
    end
  end

  defp swap_design(bundle, fun) do
    updated =
      bundle
      |> Map.fetch!("stapeln.design.json")
      |> Jason.decode!()
      |> fun.()
      |> Jason.encode!()

    Map.put(bundle, "stapeln.design.json", updated)
  end
end
