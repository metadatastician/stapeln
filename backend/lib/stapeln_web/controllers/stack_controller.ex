# SPDX-License-Identifier: MPL-2.0
defmodule StapelnWeb.StackController do
  use StapelnWeb, :controller

  alias Stapeln.Stacks
  alias Stapeln.Crypto
  alias Stapeln.Design

  def index(conn, _params) do
    with {:ok, stacks} <- Stacks.list() do
      json(conn, %{data: Enum.map(stacks, &serialize_stack/1)})
    end
  end

  def create(conn, params) do
    with {:ok, attrs} <- build_attrs(params),
         {:ok, stack} <- Stacks.create(attrs) do
      conn
      |> put_status(:created)
      |> json(%{data: serialize_stack(stack)})
    else
      {:error, message} when is_binary(message) -> bad_request(conn, message)
    end
  end

  def show(conn, %{"id" => raw_id}) do
    with {:ok, id} <- parse_id(raw_id),
         {:ok, stack} <- Stacks.fetch(id) do
      json(conn, %{data: serialize_stack(stack)})
    else
      {:error, :invalid_id} -> bad_request(conn, "invalid stack id")
      {:error, :not_found} -> not_found(conn)
    end
  end

  def update(conn, %{"id" => raw_id} = params) do
    raw_attrs = Map.delete(params, "id")

    with {:ok, id} <- parse_id(raw_id),
         {:ok, attrs} <- build_attrs(raw_attrs),
         {:ok, stack} <- Stacks.update(id, attrs) do
      json(conn, %{data: serialize_stack(stack)})
    else
      {:error, :invalid_id} -> bad_request(conn, "invalid stack id")
      {:error, :not_found} -> not_found(conn)
      {:error, message} when is_binary(message) -> bad_request(conn, message)
    end
  end

  def validate(conn, %{"id" => raw_id}) do
    with {:ok, id} <- parse_id(raw_id),
         {:ok, report} <- Stacks.validate(id) do
      json(conn, %{data: serialize_report(report)})
    else
      {:error, :invalid_id} -> bad_request(conn, "invalid stack id")
      {:error, :not_found} -> not_found(conn)
    end
  end

  def security_scan(conn, %{"id" => raw_id}) do
    with {:ok, id} <- parse_id(raw_id),
         {:ok, report} <- Stacks.security_scan(id) do
      json(conn, %{data: report})
    else
      {:error, :invalid_id} -> bad_request(conn, "invalid stack id")
      {:error, :not_found} -> not_found(conn)
    end
  end

  def gap_analysis(conn, %{"id" => raw_id}) do
    with {:ok, id} <- parse_id(raw_id),
         {:ok, report} <- Stacks.gap_analysis(id) do
      json(conn, %{data: report})
    else
      {:error, :invalid_id} -> bad_request(conn, "invalid stack id")
      {:error, :not_found} -> not_found(conn)
    end
  end

  @generate_formats %{
    "containerfile" => :containerfile,
    "docker_compose" => :docker_compose,
    "selur_compose" => :selur_compose,
    "podman_compose" => :podman_compose,
    "stapeln_bundle" => :stapeln_bundle,
    "all" => :all
  }

  def generate(conn, %{"id" => raw_id} = params) do
    format_str = Map.get(params, "format", "containerfile")

    # An unrecognised format used to fall through to :containerfile. That meant
    # `?format=stapeln_bundl` (or any typo) returned a Containerfile with HTTP
    # 200 and a `format` field echoing something the server never produced --
    # a silent wrong answer. Unknown formats are now a 400 that names what IS
    # supported.
    case Map.fetch(@generate_formats, format_str) do
      :error ->
        bad_request(
          conn,
          "unknown format #{inspect(format_str)}; supported: " <>
            (@generate_formats |> Map.keys() |> Enum.sort() |> Enum.join(", "))
        )

      {:ok, format} ->
        do_generate(conn, raw_id, format, format_str, params)
    end
  end

  defp do_generate(conn, raw_id, format, format_str, params) do
    with {:ok, id} <- parse_id(raw_id),
         {:ok, stack} <- Stacks.fetch(id),
         {:ok, result} <- run_codegen(stack, format, params) do
      case result do
        content when is_binary(content) ->
          json(conn, %{data: %{format: format_str, content: content}})

        content_map when is_map(content_map) ->
          json(conn, %{data: %{format: format_str, content: stringify_keys(content_map)}})
      end
    else
      {:error, :invalid_id} -> bad_request(conn, "invalid stack id")
      {:error, :not_found} -> not_found(conn)
      {:error, reason} when is_binary(reason) -> bad_request(conn, reason)
    end
  end

  defp run_codegen(stack, :all, _params), do: Stapeln.Codegen.generate_all(stack)

  defp run_codegen(stack, :stapeln_bundle, params) do
    Stapeln.BundleCodegen.generate(stack, bundle_opts(params))
  end

  defp run_codegen(stack, format, _params), do: Stapeln.Codegen.generate(stack, format)

  # author/email/license/owner are required by BundleCodegen and deliberately
  # not defaulted here -- see that module's docs. Passing them through as-is
  # lets it own the validation and the error message.
  # Static pairs rather than String.to_existing_atom/1: the latter raises if the
  # atom happens not to be loaded yet, turning a missing form field into a 500.
  @bundle_param_keys [
    {"author", :author},
    {"email", :email},
    {"license", :license},
    {"owner", :owner},
    {"forge", :forge},
    {"registry", :registry},
    {"repo", :repo},
    {"version", :version}
  ]

  defp bundle_opts(params) do
    for {param, key} <- @bundle_param_keys,
        value = Map.get(params, param),
        do: {key, value}
  end

  defp stringify_keys(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end

  def sign_stack(conn, %{"id" => raw_id}) do
    with {:ok, id} <- parse_id(raw_id),
         {:ok, stack} <- Stacks.fetch(id) do
      {public_key, secret_key} = Crypto.generate_keypair()

      {:ok, signature, _updated_secret} = Crypto.sign_stack(stack, secret_key)

      json(conn, %{
        data: %{
          stack_id: id,
          signature: Base.encode64(signature),
          public_key: Base.encode64(public_key),
          algorithm: "hybrid-ed25519-hash",
          signed_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
        }
      })
    else
      {:error, :invalid_id} -> bad_request(conn, "invalid stack id")
      {:error, :not_found} -> not_found(conn)
    end
  end

  def verify_stack(conn, %{"id" => raw_id} = params) do
    signature_b64 = Map.get(params, "signature")
    public_key_b64 = Map.get(params, "public_key")

    with {:ok, id} <- parse_id(raw_id),
         {:ok, stack} <- Stacks.fetch(id),
         {:ok, signature} <- decode_base64(signature_b64, "signature"),
         {:ok, public_key} <- decode_base64(public_key_b64, "public_key") do
      valid = Crypto.verify_stack(stack, signature, public_key)

      json(conn, %{
        data: %{
          stack_id: id,
          valid: valid,
          algorithm: "hybrid-ed25519-hash",
          verified_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
        }
      })
    else
      {:error, :invalid_id} ->
        bad_request(conn, "invalid stack id")

      {:error, :not_found} ->
        not_found(conn)

      {:error, :missing_param, field} ->
        bad_request(conn, "missing required parameter: #{field}")

      {:error, :invalid_base64, field} ->
        bad_request(conn, "invalid base64 in parameter: #{field}")
    end
  end

  defp decode_base64(nil, field), do: {:error, :missing_param, field}

  defp decode_base64(value, field) when is_binary(value) do
    case Base.decode64(value) do
      {:ok, decoded} -> {:ok, decoded}
      :error -> {:error, :invalid_base64, field}
    end
  end

  defp serialize_report(report) do
    %{
      score: report.score,
      findings: Enum.map(report.findings, &serialize_finding/1),
      stack: serialize_stack(report.stack)
    }
  end

  defp serialize_finding(finding) do
    %{
      id: finding.id,
      severity: Atom.to_string(finding.severity),
      message: finding.message,
      hint: finding.hint
    }
  end

  defp serialize_stack(stack) do
    %{
      id: stack.id,
      name: stack.name,
      description: stack.description,
      services: stack.services,
      design: Map.get(stack, :design),
      created_at: DateTime.to_iso8601(stack.created_at),
      updated_at: DateTime.to_iso8601(stack.updated_at)
    }
  end

  # Build the persistence attrs from the raw request params. When the params
  # look like a full-fidelity design document (they have a "canvas" key),
  # store the document verbatim under "design" and derive the flattened
  # "services" list the analyzers/Codegen consume from it. Otherwise the
  # params are already in the legacy shape (top-level "services") and pass
  # through unchanged.
  defp build_attrs(%{"canvas" => _} = params) do
    case Design.valid?(params) do
      :ok ->
        {:ok,
         %{
           "name" => derive_name(params),
           "design" => params,
           "services" => Design.derive_services(params)
         }}

      {:error, _reason} = error ->
        error
    end
  end

  defp build_attrs(params), do: {:ok, params}

  defp derive_name(params) do
    Map.get(params, "name") ||
      non_empty(get_in(params, ["metadata", "description"])) ||
      "stapeln-stack"
  end

  defp non_empty(nil), do: nil
  defp non_empty(""), do: nil
  defp non_empty(value), do: value

  defp parse_id(raw_id) do
    case Integer.parse(to_string(raw_id)) do
      {id, ""} when id > 0 -> {:ok, id}
      _ -> {:error, :invalid_id}
    end
  end

  defp bad_request(conn, message) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: message})
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{error: "stack not found"})
  end
end
