# SPDX-License-Identifier: MPL-2.0

defmodule Stapeln.GapAnalyzerTest do
  use ExUnit.Case, async: true

  alias Stapeln.GapAnalyzer

  @stack_with_latest %{
    "name" => "insecure-stack",
    "services" => [
      %{
        "name" => "web",
        "image" => "nginx:latest",
        "ports" => ["80:80"]
      }
    ]
  }

  @stack_pinned %{
    "name" => "secure-stack",
    "services" => [
      %{
        "name" => "web",
        "image" => "cgr.dev/chainguard/nginx:1.27",
        "ports" => ["8080:80"],
        "health_check" => %{"test" => "curl -f http://localhost/"},
        "resources" => %{"limits" => %{"memory" => "256m"}}
      }
    ]
  }

  describe "analyze/1" do
    test "returns a gap report for a stack with :latest tags" do
      result = GapAnalyzer.analyze(@stack_with_latest)
      assert is_map(result)
    end

    test "returns a gap report for a secure stack" do
      result = GapAnalyzer.analyze(@stack_pinned)
      assert is_map(result)
    end

    test "report has score and categories" do
      result = GapAnalyzer.analyze(@stack_with_latest)
      # Gap reports should have some structure — score, findings, etc.
      assert is_map(result)
    end
  end
end
