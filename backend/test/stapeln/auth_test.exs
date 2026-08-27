# SPDX-License-Identifier: MPL-2.0

defmodule Stapeln.AuthTest do
  use ExUnit.Case, async: true

  alias Stapeln.Auth
  alias Stapeln.Auth.{Token, UserStore}

  setup do
    # This block used to claim "Ensure clean state" and then do nothing but
    # return :ok. It is now a real assertion instead of a comforting comment.
    #
    # Cleanliness comes from config/test.exs setting persist_path: nil, so the
    # store never reads or writes /tmp/stapeln-user-store.json under test. That
    # file is what made these tests flaky: addresses are built from
    # System.unique_integer/1, which restarts low each VM run, so a run
    # reissuing an integer a PREVIOUS run had persisted got :email_taken.
    #
    # If someone re-enables persistence for the test env, this fails loudly
    # here rather than as a mystery :email_taken in an unrelated test.
    assert Stapeln.Auth.UserStore.persist_path() == nil,
           "UserStore must not persist under test — see config/test.exs"

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
