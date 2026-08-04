# SPDX-License-Identifier: MPL-2.0
defmodule StapelnWeb.StackControllerTest do
  use StapelnWeb.ConnCase, async: false

  setup do
    Stapeln.StackStore.reset!()
    :ok
  end

  test "creates, fetches, updates, and validates a stack", %{conn: conn} do
    create_params = %{
      "name" => "demo-stack",
      "description" => "testing",
      "services" => [%{"name" => "api", "kind" => "web"}]
    }

    conn = post(conn, ~p"/api/stacks", create_params)
    assert %{"data" => created} = json_response(conn, 201)
    assert created["name"] == "demo-stack"
    assert is_integer(created["id"])
    id = created["id"]

    conn = get(recycle(conn), ~p"/api/stacks/#{id}")
    assert %{"data" => fetched} = json_response(conn, 200)
    assert fetched["id"] == id

    conn = put(recycle(conn), ~p"/api/stacks/#{id}", %{"name" => "demo-stack-v2"})
    assert %{"data" => updated} = json_response(conn, 200)
    assert updated["name"] == "demo-stack-v2"

    conn = post(recycle(conn), ~p"/api/stacks/#{id}/validate", %{})
    assert %{"data" => report} = json_response(conn, 200)
    assert is_integer(report["score"])
    assert is_list(report["findings"])
    assert report["stack"]["id"] == id
  end

  test "returns not_found for unknown stack", %{conn: conn} do
    conn = get(conn, ~p"/api/stacks/999")
    assert %{"error" => "stack not found"} = json_response(conn, 404)
  end

  test "lists stacks", %{conn: conn} do
    _ = post(conn, ~p"/api/stacks", %{"name" => "a"})
    _ = post(recycle(conn), ~p"/api/stacks", %{"name" => "b"})

    conn = get(recycle(conn), ~p"/api/stacks")
    assert %{"data" => stacks} = json_response(conn, 200)
    assert Enum.count(stacks) == 2
  end

  test "rejects stack requests without API token" do
    conn = get(Phoenix.ConnTest.build_conn(), ~p"/api/stacks")
    assert %{"error" => "missing or invalid API token"} = json_response(conn, 401)
  end

  @design_doc %{
    "version" => "1.0",
    "metadata" => %{
      "created" => "2026-08-04T00:00:00.000Z",
      "author" => "Jonathan D.A. Jewell",
      "description" => "full-fidelity save test"
    },
    "canvas" => %{
      "components" => [
        %{
          "id" => "web-1",
          "type" => "Podman",
          "position" => %{"x" => 12.5, "y" => 34.0},
          "config" => %{"port" => "8080"}
        },
        %{
          "id" => "db-1",
          "type" => "Volume",
          "position" => %{"x" => 220.0, "y" => 34.0},
          "config" => %{}
        }
      ],
      "connections" => [
        %{"id" => "conn-1", "from" => "web-1", "to" => "db-1"}
      ]
    }
  }

  test "creates a stack from a full-fidelity design document and round-trips it verbatim", %{
    conn: conn
  } do
    conn = post(conn, ~p"/api/stacks", @design_doc)
    assert %{"data" => created} = json_response(conn, 201)
    assert created["name"] == "full-fidelity save test"
    assert created["design"] == @design_doc
    assert [web, db] = created["services"]
    assert web["name"] == "web-1"
    assert web["kind"] == "Podman"
    assert web["port"] == 8080
    assert web["depends_on"] == ["db-1"]
    assert db["name"] == "db-1"
    id = created["id"]

    # show returns the design doc verbatim (position/config/connections all
    # survive — this is the bug the old hand-rolled serializeStack couldn't
    # avoid, since it never sent them to the backend in the first place)
    conn = get(recycle(conn), ~p"/api/stacks/#{id}")
    assert %{"data" => fetched} = json_response(conn, 200)
    assert fetched["design"] == @design_doc
  end

  test "rejects a design document with a malformed canvas", %{conn: conn} do
    bad = put_in(@design_doc, ["canvas"], %{"components" => "not-a-list"})
    conn = post(conn, ~p"/api/stacks", bad)
    assert %{"error" => _reason} = json_response(conn, 400)
  end

  test "end-to-end: save a design doc then run security-scan on the returned id", %{conn: conn} do
    conn = post(conn, ~p"/api/stacks", @design_doc)
    assert %{"data" => %{"id" => id}} = json_response(conn, 201)

    # This is the path the old code could never reach: ApiClient.saveStack
    # returned the raw response body as a string, App.res parsed it with
    # Int.fromString (always None for a JSON object body), defaulted to 0,
    # and POST /api/stacks/0/security-scan always 400'd.
    conn = post(recycle(conn), ~p"/api/stacks/#{id}/security-scan", %{})
    assert %{"data" => _report} = json_response(conn, 200)
  end

  test "end-to-end: save a design doc then run gap-analysis on the returned id", %{conn: conn} do
    conn = post(conn, ~p"/api/stacks", @design_doc)
    assert %{"data" => %{"id" => id}} = json_response(conn, 201)

    conn = post(recycle(conn), ~p"/api/stacks/#{id}/gap-analysis", %{})
    assert %{"data" => _report} = json_response(conn, 200)
  end
end
