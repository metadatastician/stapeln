# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule Stapeln.CodegenTest do
  use ExUnit.Case, async: true

  alias Stapeln.Codegen

  @sample_stack %{
    name: "test-stack",
    services: [
      %{
        name: "web",
        image: "nginx:1.27-alpine",
        ports: ["8080:80"],
        environment: %{"ENV" => "production"},
        volumes: ["/data:/usr/share/nginx/html:ro"]
      },
      %{
        name: "api",
        image: "cgr.dev/chainguard/static:latest",
        ports: ["3000:3000"],
        environment: %{"DATABASE_URL" => "postgres://localhost/db"}
      }
    ]
  }

  describe "generate/2" do
    test "generates Containerfile" do
      assert {:ok, content} = Codegen.generate(@sample_stack, :containerfile)
      assert is_binary(content)
      assert String.contains?(content, "nginx")
    end

    test "generates docker-compose" do
      assert {:ok, content} = Codegen.generate(@sample_stack, :docker_compose)
      assert is_binary(content)
      assert String.contains?(content, "services")
    end

    test "generates selur-compose" do
      assert {:ok, content} = Codegen.generate(@sample_stack, :selur_compose)
      assert is_binary(content)
    end

    test "generates podman-compose" do
      assert {:ok, content} = Codegen.generate(@sample_stack, :podman_compose)
      assert is_binary(content)
    end
  end

  describe "generate_all/1" do
    test "generates all formats" do
      assert {:ok, results} = Codegen.generate_all(@sample_stack)
      assert Map.has_key?(results, :containerfile)
      assert Map.has_key?(results, :docker_compose)
      assert Map.has_key?(results, :selur_compose)
      assert Map.has_key?(results, :podman_compose)
      assert map_size(results) == 4
    end
  end
end
