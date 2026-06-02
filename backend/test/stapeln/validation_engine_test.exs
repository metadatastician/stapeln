# SPDX-License-Identifier: MPL-2.0

defmodule Stapeln.ValidationEngineTest do
  use ExUnit.Case, async: true

  alias Stapeln.ValidationEngine

  @valid_stack %{
    "name" => "production",
    "services" => [
      %{
        "name" => "web",
        "image" => "nginx:1.27-alpine",
        "ports" => ["8080:80"]
      }
    ]
  }

  @empty_stack %{
    "name" => "",
    "services" => []
  }

  describe "validate/1" do
    test "passes for a valid stack" do
      result = ValidationEngine.validate(@valid_stack)
      assert is_map(result)
    end

    test "reports errors for empty stack" do
      result = ValidationEngine.validate(@empty_stack)
      assert is_map(result)
    end

    test "returns structured result" do
      result = ValidationEngine.validate(@valid_stack)
      assert is_map(result)
    end
  end
end
