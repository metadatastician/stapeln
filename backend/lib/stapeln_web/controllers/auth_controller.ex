# SPDX-License-Identifier: PMPL-1.0-or-later
# auth_controller.ex - Authentication endpoints for stapeln

defmodule StapelnWeb.AuthController do
  use StapelnWeb, :controller

  alias Stapeln.Auth
  alias Stapeln.Auth.Token

  @doc "POST /api/auth/register"
  def register(conn, %{"email" => email, "password" => password}) do
    case Auth.register(email, password) do
      {:ok, token} ->
        conn
        |> put_status(:created)
        |> text(token)

      {:error, :email_taken} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "email already registered"})

      {:error, :invalid_email} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid email address"})

      {:error, :password_too_short} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "password must be at least 6 characters"})
    end
  end

  def register(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "email and password required"})
  end

  @doc "POST /api/auth/login"
  def login(conn, %{"email" => email, "password" => password}) do
    case Auth.login(email, password) do
      {:ok, token} ->
        text(conn, token)

      {:error, :invalid_credentials} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "invalid email or password"})
    end
  end

  def login(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "email and password required"})
  end

  @doc "POST /api/auth/login — returns access + refresh token pair."
  def login_with_refresh(conn, %{"email" => email, "password" => password}) do
    case Auth.login(email, password) do
      {:ok, _access_token} ->
        # Generate token pair (access + refresh).
        case Auth.get_user_by_email(email) do
          {:ok, user} ->
            json(conn, %{
              access_token: Token.generate(user.id),
              refresh_token: Token.generate_refresh(user.id),
              token_type: "Bearer",
              expires_in: 604_800
            })

          _ ->
            conn |> put_status(:unauthorized) |> json(%{error: "invalid credentials"})
        end

      {:error, :invalid_credentials} ->
        conn |> put_status(:unauthorized) |> json(%{error: "invalid email or password"})
    end
  end

  @doc "POST /api/auth/refresh — exchange refresh token for new token pair."
  def refresh(conn, %{"refresh_token" => refresh_token}) do
    case Token.refresh(refresh_token) do
      {:ok, %{access: access, refresh: refresh}} ->
        json(conn, %{
          access_token: access,
          refresh_token: refresh,
          token_type: "Bearer",
          expires_in: 604_800
        })

      {:error, reason} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "refresh failed: #{reason}"})
    end
  end

  def refresh(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "refresh_token required"})
  end

  @doc "GET /api/auth/me"
  def me(conn, _params) do
    with {:ok, token} <- extract_bearer_token(conn),
         {:ok, user_id} <- Token.verify(token),
         {:ok, user} <- Auth.get_user(user_id) do
      json(conn, %{
        data: %{
          id: user.id,
          email: user.email,
          created_at: user.created_at
        }
      })
    else
      {:error, _} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "invalid or expired token"})
    end
  end

  defp extract_bearer_token(conn) do
    case Plug.Conn.get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] -> {:ok, String.trim(token)}
      _ -> {:error, :no_token}
    end
  end
end
