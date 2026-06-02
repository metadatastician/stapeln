# SPDX-License-Identifier: MPL-2.0

defmodule Stapeln.AuthTest do
  use ExUnit.Case, async: true

  alias Stapeln.Auth
  alias Stapeln.Auth.{Token, UserStore}

  setup do
    # Ensure clean state — UserStore is an in-memory GenServer
    :ok
  end

  describe "register/2" do
    test "registers a user with valid email and password" do
      email = "test-#{System.unique_integer([:positive])}@example.com"
      assert {:ok, token} = Auth.register(email, "password123")
      assert is_binary(token)
      assert String.length(token) > 10
    end

    test "rejects empty or short email" do
      assert {:error, :invalid_email} = Auth.register("ab", "password123")
    end

    test "rejects short password" do
      assert {:error, :password_too_short} = Auth.register("test@example.com", "short")
    end

    test "normalises email to lowercase" do
      email = "TEST-#{System.unique_integer([:positive])}@Example.COM"
      {:ok, token} = Auth.register(email, "password123")
      {:ok, user_id} = Token.verify(token)

      {:ok, user} = Auth.get_user(user_id)
      assert user.email == String.downcase(String.trim(email))
    end
  end

  describe "login/2" do
    test "logs in with correct credentials" do
      email = "login-#{System.unique_integer([:positive])}@example.com"
      {:ok, _} = Auth.register(email, "correct-password")

      assert {:ok, token} = Auth.login(email, "correct-password")
      assert is_binary(token)
    end

    test "rejects wrong password" do
      email = "wrong-pw-#{System.unique_integer([:positive])}@example.com"
      {:ok, _} = Auth.register(email, "correct-password")

      assert {:error, :invalid_credentials} = Auth.login(email, "wrong-password")
    end

    test "rejects unknown email" do
      assert {:error, :invalid_credentials} =
               Auth.login("nonexistent@example.com", "anything")
    end
  end

  describe "Token" do
    test "generate and verify round-trips" do
      token = Token.generate("user_42")
      assert {:ok, user_id} = Token.verify(token)
      assert user_id == "user_42"
    end

    test "rejects tampered token" do
      token = Token.generate("user_42")
      tampered = token <> "x"
      assert {:error, _} = Token.verify(tampered)
    end
  end
end
