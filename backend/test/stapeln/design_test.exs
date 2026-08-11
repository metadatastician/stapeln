# SPDX-License-Identifier: MPL-2.0
defmodule Stapeln.DesignTest do
  use ExUnit.Case, async: true

  alias Stapeln.Design

  @valid_design %{
    "version" => "1.0",
    "metadata" => %{
      "created" => "2026-08-04T00:00:00.000Z",
      "author" => "Jonathan D.A. Jewell",
      "description" => "test design"
    },
    "canvas" => %{
      "components" => [
        %{
          "id" => "web-1",
          "type" => "Podman",
          "position" => %{"x" => 0.0, "y" => 0.0},
          "config" => %{"port" => "8080"}
        },
        %{
          "id" => "db-1",
          "type" => "Volume",
          "position" => %{"x" => 200.0, "y" => 0.0},
          "config" => %{}
        }
      ],
      "connections" => [
        %{"id" => "conn-1", "from" => "web-1", "to" => "db-1"}
      ]
    }
  }

  @legacy_shape %{
    "name" => "stapeln-stack",
    "services" => [%{"name" => "api", "kind" => "web", "port" => 3000}]
  }

  describe "valid?/1" do
    test "accepts a well-formed design document" do
      assert Design.valid?(@valid_design) == :ok
    end

    test "accepts the legacy top-level services shape" do
      assert Design.valid?(@legacy_shape) == :ok
    end

    test "rejects a design document with a non-map canvas" do
      bad = %{@valid_design | "canvas" => "not-a-map"}
      assert {:error, _reason} = Design.valid?(bad)
    end

    test "rejects a design document missing canvas.connections" do
      bad = put_in(@valid_design, ["canvas"], %{"components" => []})
      assert {:error, _reason} = Design.valid?(bad)
    end

    test "rejects a design document with connections not a list" do
      bad = put_in(@valid_design, ["canvas", "connections"], "nope")
      assert {:error, _reason} = Design.valid?(bad)
    end

    test "rejects an unrecognised shape" do
      assert {:error, _reason} = Design.valid?(%{"foo" => "bar"})
    end

    test "rejects a non-map" do
      assert {:error, _reason} = Design.valid?("not a map")
    end
  end

  describe "derive_services/1" do
    test "flattens canvas components to name/kind/port" do
      [web, db] = Design.derive_services(@valid_design)

      assert web["name"] == "web-1"
      assert web["kind"] == "Podman"
      assert web["port"] == 8080

      assert db["name"] == "db-1"
      assert db["kind"] == "Volume"
      assert db["port"] == 0
    end

    test "folds connections into depends_on on the source component" do
      [web, db] = Design.derive_services(@valid_design)

      assert web["depends_on"] == ["db-1"]
      refute Map.has_key?(db, "depends_on")
    end

    test "supports fan-out: one component depending on multiple others" do
      design =
        put_in(@valid_design, ["canvas", "connections"], [
          %{"id" => "c1", "from" => "web-1", "to" => "db-1"},
          %{"id" => "c2", "from" => "web-1", "to" => "cache-1"}
        ])

      [web, _db] = Design.derive_services(design)
      assert web["depends_on"] == ["db-1", "cache-1"]
    end

    test "returns the legacy services list unchanged" do
      assert Design.derive_services(@legacy_shape) == @legacy_shape["services"]
    end

    test "returns an empty list for an unrecognised shape" do
      assert Design.derive_services(%{"foo" => "bar"}) == []
    end

    test "defaults port to 0 when config has no port key" do
      design =
        put_in(@valid_design, ["canvas", "components"], [
          %{"id" => "solo", "type" => "Network", "position" => %{"x" => 0.0, "y" => 0.0}}
        ])

      [solo] = Design.derive_services(design)
      assert solo["port"] == 0
    end
  end
end
