# SPDX-License-Identifier: MPL-2.0
# StapelnWeb.PipelineController - API controller for assembly pipeline operations.

defmodule StapelnWeb.PipelineController do
  use StapelnWeb, :controller

  alias Stapeln.PipelineEngine
  alias Stapeln.PipelineCodegen
  alias Stapeln.VeriSimDB

  # ---------------------------------------------------------------------------
  # Validate a pipeline (stateless — accepts pipeline JSON directly)
  # ---------------------------------------------------------------------------

  @doc "POST /api/pipelines/validate — validate a pipeline graph."
  def validate(conn, %{"pipeline" => pipeline}) when is_map(pipeline) do
    result = PipelineEngine.validate(pipeline)

    VeriSimDB.record(:validation, %{
      type: "pipeline",
      valid: result.valid,
      error_count: length(result.errors),
      security_score: result.security_score
    })

    json(conn, %{data: serialize_validation(result)})
  end

  def validate(conn, _params) do
    bad_request(conn, "missing required 'pipeline' object in request body")
  end

  # ---------------------------------------------------------------------------
  # Generate artefacts from a pipeline
  # ---------------------------------------------------------------------------

  @doc "POST /api/pipelines/generate — generate container artefacts."
  def generate(conn, %{"pipeline" => pipeline} = params) when is_map(pipeline) do
    format_str = Map.get(params, "format", "containerfile")

    case parse_format(format_str) do
      {:ok, format} ->
        result = generate_format(pipeline, format)

        case result do
          {:ok, content} when is_binary(content) ->
            json(conn, %{data: %{format: format_str, content: content}})

          {:ok, content} when is_map(content) ->
            json(conn, %{data: %{format: format_str, content: content}})

          {:error, reason} ->
            bad_request(conn, "codegen failed: #{reason}")
        end

      {:error, msg} ->
        bad_request(conn, msg)
    end
  end

  def generate(conn, _params) do
    bad_request(conn, "missing required 'pipeline' object in request body")
  end

  # ---------------------------------------------------------------------------
  # Optimize a pipeline
  # ---------------------------------------------------------------------------

  @doc "POST /api/pipelines/optimize — return an optimized pipeline."
  def optimize(conn, %{"pipeline" => pipeline}) when is_map(pipeline) do
    optimized = PipelineEngine.optimize(pipeline)

    # Also validate the optimized result so the caller knows the state
    validation = PipelineEngine.validate(optimized)

    json(conn, %{
      data: %{
        pipeline: optimized,
        validation: serialize_validation(validation)
      }
    })
  end

  def optimize(conn, _params) do
    bad_request(conn, "missing required 'pipeline' object in request body")
  end

  # ---------------------------------------------------------------------------
  # Dry-run simulation
  # ---------------------------------------------------------------------------

  @doc """
  POST /api/pipelines/dry-run — simulate packet flow through a pipeline.

  Accepts a pipeline graph and optional simulation parameters:
  - packet_rate: packets per second (default 4.0)
  - latency_ms: base latency in milliseconds (default 50.0)
  - drop_rate: packet drop probability 0.0-1.0 (default 0.02)
  - jitter_ms: latency variance in ms (default 10.0)
  - seed: PRNG seed for deterministic results (default 42)
  - duration_steps: number of packets to simulate (default 100)

  Returns events array + summary metrics for frontend animation playback.
  """
  def dry_run(conn, %{"pipeline" => pipeline} = params) when is_map(pipeline) do
    sim_params =
      params
      |> Map.take(["packet_rate", "latency_ms", "drop_rate", "jitter_ms", "seed", "duration_steps"])
      |> Enum.reduce(%{}, fn
        {key, val}, acc when is_number(val) ->
          Map.put(acc, String.to_existing_atom(key), val)

        {key, val}, acc when is_binary(val) ->
          case Float.parse(val) do
            {num, _} -> Map.put(acc, String.to_existing_atom(key), num)
            :error ->
              case Integer.parse(val) do
                {num, _} -> Map.put(acc, String.to_existing_atom(key), num)
                :error -> acc
              end
          end

        _, acc ->
          acc
      end)

    result = Stapeln.SimulationEngine.dry_run(pipeline, sim_params)

    VeriSimDB.record(:simulation, %{
      type: "dry_run",
      valid: result.valid,
      packets_sent: result.packets_sent,
      packets_delivered: result.packets_delivered,
      packets_dropped: result.packets_dropped,
      avg_latency_ms: result.avg_latency_ms,
      security_findings: length(result.security_findings)
    })

    json(conn, %{data: result})
  end

  def dry_run(conn, _params) do
    bad_request(conn, "missing required 'pipeline' object in request body")
  end

  # ---------------------------------------------------------------------------
  # Pipeline templates
  # ---------------------------------------------------------------------------

  @doc "GET /api/pipelines/templates — return built-in pipeline templates."
  def templates(conn, _params) do
    json(conn, %{data: builtin_templates()})
  end

  # ---------------------------------------------------------------------------
  # CRUD: create
  # ---------------------------------------------------------------------------

  @doc "POST /api/pipelines — save a pipeline."
  def create(conn, %{"pipeline" => pipeline} = params) when is_map(pipeline) do
    name = Map.get(params, "name", Map.get(pipeline, "name", "Untitled Pipeline"))
    description = Map.get(params, "description", Map.get(pipeline, "description", ""))

    # Validate before saving
    validation = PipelineEngine.validate(pipeline)

    unless validation.valid do
      bad_request(conn, "pipeline has validation errors: #{Enum.join(validation.errors, "; ")}")
    else
      record = %{
        name: name,
        description: description,
        pipeline: pipeline,
        validation: serialize_validation(validation),
        created_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
        updated_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
      }

      case Stapeln.PipelineStore.create(record) do
        {:ok, saved} ->
          VeriSimDB.record(:stack_created, %{type: "pipeline", name: name})

          conn
          |> put_status(:created)
          |> json(%{data: saved})

        {:error, reason} ->
          bad_request(conn, "failed to save pipeline: #{inspect(reason)}")
      end
    end
  end

  def create(conn, _params) do
    bad_request(conn, "missing required 'pipeline' object in request body")
  end

  # ---------------------------------------------------------------------------
  # CRUD: show
  # ---------------------------------------------------------------------------

  @doc "GET /api/pipelines/:id — fetch a saved pipeline."
  def show(conn, %{"id" => raw_id}) do
    with {:ok, id} <- parse_id(raw_id),
         {:ok, pipeline} <- Stapeln.PipelineStore.get(id) do
      json(conn, %{data: pipeline})
    else
      {:error, :invalid_id} -> bad_request(conn, "invalid pipeline id")
      {:error, :not_found} -> not_found(conn)
    end
  end

  # ---------------------------------------------------------------------------
  # CRUD: update
  # ---------------------------------------------------------------------------

  @doc "PUT /api/pipelines/:id — update a saved pipeline."
  def update(conn, %{"id" => raw_id, "pipeline" => pipeline} = params) when is_map(pipeline) do
    with {:ok, id} <- parse_id(raw_id) do
      validation = PipelineEngine.validate(pipeline)

      unless validation.valid do
        bad_request(conn, "pipeline has validation errors: #{Enum.join(validation.errors, "; ")}")
      else
        attrs = %{
          name: Map.get(params, "name"),
          description: Map.get(params, "description"),
          pipeline: pipeline,
          validation: serialize_validation(validation),
          updated_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
        }
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Map.new()

        case Stapeln.PipelineStore.update(id, attrs) do
          {:ok, updated} ->
            VeriSimDB.record(:stack_updated, %{type: "pipeline", id: id})
            json(conn, %{data: updated})

          {:error, :not_found} ->
            not_found(conn)

          {:error, reason} ->
            bad_request(conn, "failed to update pipeline: #{inspect(reason)}")
        end
      end
    else
      {:error, :invalid_id} -> bad_request(conn, "invalid pipeline id")
    end
  end

  def update(conn, %{"id" => _raw_id}) do
    bad_request(conn, "missing required 'pipeline' object in request body")
  end

  # ---------------------------------------------------------------------------
  # CRUD: delete
  # ---------------------------------------------------------------------------

  @doc "DELETE /api/pipelines/:id — delete a saved pipeline."
  def delete(conn, %{"id" => raw_id}) do
    with {:ok, id} <- parse_id(raw_id),
         {:ok, _} <- Stapeln.PipelineStore.delete(id) do
      VeriSimDB.record(:stack_deleted, %{type: "pipeline", id: id})
      json(conn, %{data: %{deleted: true, id: id}})
    else
      {:error, :invalid_id} -> bad_request(conn, "invalid pipeline id")
      {:error, :not_found} -> not_found(conn)
    end
  end

  # ---------------------------------------------------------------------------
  # Format helpers
  # ---------------------------------------------------------------------------

  @valid_formats ~w(containerfile selur_compose podman_compose k8s helm oci_bundle all)

  defp parse_format(format_str) when format_str in @valid_formats do
    {:ok, String.to_existing_atom(format_str)}
  end

  defp parse_format(format_str) do
    {:error, "unknown format '#{format_str}'; valid formats: #{Enum.join(@valid_formats, ", ")}"}
  end

  defp generate_format(pipeline, :all) do
    results =
      [:containerfile, :selur_compose, :podman_compose, :k8s, :oci_bundle]
      |> Enum.reduce_while(%{}, fn fmt, acc ->
        case generate_format(pipeline, fmt) do
          {:ok, content} -> {:cont, Map.put(acc, Atom.to_string(fmt), content)}
          {:error, _} = err -> {:halt, err}
        end
      end)

    case results do
      {:error, _} = err -> err
      map when is_map(map) -> {:ok, map}
    end
  end

  defp generate_format(pipeline, :containerfile), do: PipelineCodegen.to_containerfile(pipeline)
  defp generate_format(pipeline, :selur_compose), do: PipelineCodegen.to_selur_compose(pipeline)
  defp generate_format(pipeline, :podman_compose), do: PipelineCodegen.to_podman_compose(pipeline)
  defp generate_format(pipeline, :k8s), do: PipelineCodegen.to_k8s(pipeline)
  defp generate_format(pipeline, :helm), do: PipelineCodegen.to_helm(pipeline)
  defp generate_format(pipeline, :oci_bundle), do: PipelineCodegen.to_oci_bundle(pipeline)

  # ---------------------------------------------------------------------------
  # Serialization
  # ---------------------------------------------------------------------------

  defp serialize_validation(result) do
    %{
      valid: result.valid,
      errors: result.errors,
      warnings: result.warnings,
      security_score: result.security_score,
      estimated_size: result.estimated_size
    }
  end

  # ---------------------------------------------------------------------------
  # Built-in templates
  # ---------------------------------------------------------------------------

  defp builtin_templates do
    [
      %{
        id: "web-service",
        name: "Web Service",
        description: "Single web service with Chainguard base, build step, and registry push",
        pipeline: %{
          "nodes" => [
            %{"id" => "base", "type" => "source", "config" => %{"image" => "cgr.dev/chainguard/wolfi-base:latest"}},
            %{"id" => "workdir", "type" => "workdir", "config" => %{"path" => "/app"}},
            %{"id" => "deps", "type" => "copy", "config" => %{"src" => "package.json", "dst" => "."}},
            %{"id" => "install", "type" => "run", "config" => %{"commands" => ["apk add nodejs npm", "npm ci --production"]}},
            %{"id" => "src", "type" => "copy", "config" => %{"src" => ".", "dst" => "."}},
            %{"id" => "port", "type" => "expose", "config" => %{"port" => 3000}},
            %{"id" => "gate", "type" => "security_gate", "config" => %{"tool" => "trivy", "severity" => "HIGH,CRITICAL"}},
            %{"id" => "push", "type" => "push", "config" => %{"registry" => "ghcr.io/hyperpolymath/my-service", "tag" => "latest"}}
          ],
          "connections" => [
            %{"from" => "base", "to" => "workdir"},
            %{"from" => "workdir", "to" => "deps"},
            %{"from" => "deps", "to" => "install"},
            %{"from" => "install", "to" => "src"},
            %{"from" => "src", "to" => "port"},
            %{"from" => "port", "to" => "gate"},
            %{"from" => "gate", "to" => "push"}
          ],
          "metadata" => %{"name" => "web-service"}
        }
      },
      %{
        id: "multi-stage-build",
        name: "Multi-Stage Build",
        description: "Builder stage compiles, runtime stage runs — minimal final image",
        pipeline: %{
          "nodes" => [
            %{"id" => "builder", "type" => "source", "config" => %{"image" => "cgr.dev/chainguard/wolfi-base:latest", "alias" => "builder"}},
            %{"id" => "build-workdir", "type" => "workdir", "config" => %{"path" => "/build"}},
            %{"id" => "build-copy", "type" => "copy", "config" => %{"src" => ".", "dst" => "."}},
            %{"id" => "build-run", "type" => "run", "config" => %{"commands" => ["apk add build-base", "make build"]}},
            %{"id" => "runtime", "type" => "source", "config" => %{"image" => "cgr.dev/chainguard/static:latest", "alias" => "runtime"}},
            %{"id" => "rt-workdir", "type" => "workdir", "config" => %{"path" => "/app"}},
            %{"id" => "rt-copy", "type" => "copy", "config" => %{"src" => "/build/output", "dst" => "/app/", "from" => "builder"}},
            %{"id" => "gate", "type" => "security_gate", "config" => %{"tool" => "trivy"}},
            %{"id" => "push", "type" => "push", "config" => %{"registry" => "ghcr.io/hyperpolymath/my-app", "tag" => "latest"}}
          ],
          "connections" => [
            %{"from" => "builder", "to" => "build-workdir"},
            %{"from" => "build-workdir", "to" => "build-copy"},
            %{"from" => "build-copy", "to" => "build-run"},
            %{"from" => "runtime", "to" => "rt-workdir"},
            %{"from" => "rt-workdir", "to" => "rt-copy"},
            %{"from" => "rt-copy", "to" => "gate"},
            %{"from" => "gate", "to" => "push"}
          ],
          "metadata" => %{"name" => "multi-stage-build"}
        }
      },
      %{
        id: "microservice-stack",
        name: "Microservice Stack",
        description: "Web frontend + API backend + PostgreSQL database",
        pipeline: %{
          "nodes" => [
            %{"id" => "frontend", "type" => "source", "config" => %{"image" => "cgr.dev/chainguard/wolfi-base:latest", "alias" => "frontend"}},
            %{"id" => "fe-workdir", "type" => "workdir", "config" => %{"path" => "/app"}},
            %{"id" => "fe-copy", "type" => "copy", "config" => %{"src" => "frontend/", "dst" => "."}},
            %{"id" => "fe-build", "type" => "run", "config" => %{"commands" => ["apk add nodejs npm", "npm ci", "npm run build"]}},
            %{"id" => "fe-port", "type" => "expose", "config" => %{"port" => 3000}},
            %{"id" => "api", "type" => "source", "config" => %{"image" => "cgr.dev/chainguard/wolfi-base:latest", "alias" => "api"}},
            %{"id" => "api-workdir", "type" => "workdir", "config" => %{"path" => "/app"}},
            %{"id" => "api-copy", "type" => "copy", "config" => %{"src" => "api/", "dst" => "."}},
            %{"id" => "api-build", "type" => "run", "config" => %{"commands" => ["apk add elixir", "mix deps.get", "mix release"]}},
            %{"id" => "api-port", "type" => "expose", "config" => %{"port" => 4010}},
            %{"id" => "db", "type" => "source", "config" => %{"image" => "cgr.dev/chainguard/postgres:latest", "alias" => "db"}},
            %{"id" => "db-env", "type" => "env", "config" => %{"key" => "POSTGRES_DB", "value" => "app_prod"}},
            %{"id" => "db-port", "type" => "expose", "config" => %{"port" => 5432}},
            %{"id" => "db-vol", "type" => "volume", "config" => %{"path" => "/var/lib/postgresql/data"}},
            %{"id" => "gate", "type" => "security_gate", "config" => %{"tool" => "trivy", "severity" => "HIGH,CRITICAL"}},
            %{"id" => "push-fe", "type" => "push", "config" => %{"registry" => "ghcr.io/hyperpolymath/frontend", "tag" => "latest"}},
            %{"id" => "push-api", "type" => "push", "config" => %{"registry" => "ghcr.io/hyperpolymath/api", "tag" => "latest"}}
          ],
          "connections" => [
            %{"from" => "frontend", "to" => "fe-workdir"},
            %{"from" => "fe-workdir", "to" => "fe-copy"},
            %{"from" => "fe-copy", "to" => "fe-build"},
            %{"from" => "fe-build", "to" => "fe-port"},
            %{"from" => "fe-port", "to" => "gate"},
            %{"from" => "api", "to" => "api-workdir"},
            %{"from" => "api-workdir", "to" => "api-copy"},
            %{"from" => "api-copy", "to" => "api-build"},
            %{"from" => "api-build", "to" => "api-port"},
            %{"from" => "api-port", "to" => "gate"},
            %{"from" => "db", "to" => "db-env"},
            %{"from" => "db-env", "to" => "db-port"},
            %{"from" => "db-port", "to" => "db-vol"},
            %{"from" => "gate", "to" => "push-fe"},
            %{"from" => "gate", "to" => "push-api"}
          ],
          "metadata" => %{"name" => "microservice-stack"}
        }
      }
    ]
  end

  # ---------------------------------------------------------------------------
  # Shared helpers (same pattern as StackController)
  # ---------------------------------------------------------------------------

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
    |> json(%{error: "pipeline not found"})
  end
end
