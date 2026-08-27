# SPDX-License-Identifier: MPL-2.0
# Stapeln.BundleCodegen - lowers a stack design to the 9-file stapeln deployment bundle.

defmodule Stapeln.BundleCodegen do
  @moduledoc """
  Compiles a stack design into the canonical `container/stapeln/` deployment
  bundle.

  This is the compiler ruling made real: stapeln lowers a visual topology to a
  set of deployment *files*, and the satellites (selur, vordr, rokur, svalinn,
  cerro-torre) consume those files rather than calling each other's APIs.

  ## The templates are byte-identical copies

  `priv/bundle_templates/` holds the eight files from
  `rsr-template-repo:build/container/stapeln/` **verbatim**, tokens and all,
  copied at `a983c006`. They are deliberately *not* converted to EEx: keeping
  them byte-identical means `diff` against the canonical bundle stays
  meaningful, and it makes the placeholder guard trivially honest -- "no
  residual `{{`" is exactly the right check when the input genuinely contains
  `{{TOKEN}}`.

  If the canonical bundle changes, re-copy and diff. Do not hand-edit these.

  ## Where each token comes from

  Sixty-five substitutions across thirteen tokens, in three tiers.

  **Derived from the design** -- always available, never guessed:

    * `PROJECT_NAME` (x10)        - the stack's name
    * `SERVICE_NAME` (x25)        - the first service's name, else the stack name
    * `PORT` (x11)                - the first service's port, else 8080
    * `PROJECT_DESCRIPTION` (x1)  - the stack's description, else generated
    * `CURRENT_DATE` (x1)         - today, UTC

  **Documented defaults** -- benign if wrong, and visible in the output:

    * `FORGE` (x2)    - "github.com"
    * `REGISTRY` (x4) - "ghcr.io"
    * `REPO` (x2)     - the project name
    * `VERSION` (x4)  - "0.1.0"

  **Required** -- `generate/2` returns an error rather than inventing these:

    * `AUTHOR` (x1), `EMAIL` (x2), `LICENSE` (x1), `OWNER` (x2)

  ### Why those four are required and the others are not

  A wrong registry is visible and harmless -- you notice at push time. A wrong
  **author, email, licence or owner** is a *falsehood in a provenance
  document*: `manifest.toml` is the file cerro-torre reads to attribute a
  build, and this estate's licence policy is explicit that licence identifiers
  are never to be guessed or swept.

  Defaulting them would be worse than leaving `{{AUTHOR}}` in place, because
  `assert_no_placeholders!/2` would then pass on a bundle that is
  placeholder-free and confidently wrong. A visible `{{` is a bug report; a
  plausible wrong value is not.
  """

  alias Stapeln.Codegen

  @typedoc "Bundle file name => file content."
  @type bundle :: %{String.t() => String.t()}

  # The eight verbatim templates. stapeln.design.json is the ninth file and is
  # generated here rather than copied, so it is not in this list.
  @bundle_templates ~w(
    .gatekeeper.yaml
    compose.example.toml
    compose.toml
    ct-build.sh
    deploy.k9.ncl
    manifest.toml
    rokur.toml
    vordr.toml
  )

  @design_file "stapeln.design.json"

  @required_opts [:author, :email, :license, :owner]

  @default_forge "github.com"
  @default_registry "ghcr.io"
  @default_version "0.1.0"
  @default_port 8080

  @doc """
  Lower `stack` to the nine-file bundle.

  Returns `{:ok, %{"filename" => contents}}` with exactly nine entries, or
  `{:error, reason}` when a required option is missing or a template fails the
  placeholder check.

  ## Options

  `:author`, `:email`, `:license` and `:owner` are **required** -- see the
  module docs for why these four and not the others. `:forge`, `:registry`,
  `:repo` and `:version` are optional and documented above.
  """
  @spec generate(map(), keyword()) :: {:ok, bundle()} | {:error, String.t()}
  def generate(stack, opts \\ []) when is_map(stack) and is_list(opts) do
    with {:ok, tokens} <- build_tokens(stack, opts),
         {:ok, files} <- render_all(tokens) do
      {:ok, Map.put(files, @design_file, design_json(stack))}
    end
  end

  @doc """
  Raise if `content` still contains an unsubstituted `{{TOKEN}}`.

  This is the guard that stops a half-minted bundle shipping. It is deliberately
  a raise and not a soft return: a bundle with a literal `{{OWNER}}` in its
  manifest is not a degraded bundle, it is a broken one, and the estate has
  already been bitten by placeholder checks that quietly verified nothing.
  """
  @spec assert_no_placeholders!(String.t(), String.t()) :: String.t()
  def assert_no_placeholders!(content, filename) when is_binary(content) do
    case Regex.scan(~r/\{\{[A-Z_][A-Z0-9_]*\}\}/, content) do
      [] ->
        content

      found ->
        residual = found |> List.flatten() |> Enum.uniq() |> Enum.sort() |> Enum.join(", ")

        raise ArgumentError,
              "#{filename}: #{length(found)} unsubstituted placeholder(s) remain: #{residual}. " <>
                "Every token must have a source; see Stapeln.BundleCodegen's module docs."
    end
  end

  @doc "The nine file names this module emits, sorted."
  @spec bundle_files() :: [String.t()]
  def bundle_files, do: Enum.sort([@design_file | @bundle_templates])

  @doc "Directory holding the verbatim template copies."
  @spec template_dir() :: String.t()
  def template_dir, do: Application.app_dir(:stapeln, "priv/bundle_templates")

  # ---------------------------------------------------------------------------
  # Token sourcing
  # ---------------------------------------------------------------------------

  defp build_tokens(stack, opts) do
    case Enum.reject(@required_opts, &present?(opts[&1])) do
      [] ->
        {:ok, do_build_tokens(stack, opts)}

      missing ->
        {:error,
         "missing required option(s): #{Enum.map_join(missing, ", ", &to_string/1)}. " <>
           "These four are not defaulted because guessing an author, email, licence " <>
           "or owner writes a falsehood into manifest.toml, which is a provenance document."}
    end
  end

  defp do_build_tokens(stack, opts) do
    project = stack_name(stack)
    services = Codegen.normalise_services(stack)
    primary = List.first(services)

    %{
      "PROJECT_NAME" => project,
      "SERVICE_NAME" => (primary && Codegen.service_name(primary)) || project,
      "PORT" => to_string((primary && Codegen.service_port(primary)) || @default_port),
      "PROJECT_DESCRIPTION" => description(stack, project),
      "CURRENT_DATE" => Date.utc_today() |> Date.to_iso8601(),
      "VERSION" => opt(opts, :version, @default_version),
      "FORGE" => opt(opts, :forge, @default_forge),
      "REGISTRY" => opt(opts, :registry, @default_registry),
      "REPO" => opt(opts, :repo, project),
      "AUTHOR" => to_string(opts[:author]),
      "EMAIL" => to_string(opts[:email]),
      "LICENSE" => to_string(opts[:license]),
      "OWNER" => to_string(opts[:owner])
    }
  end

  defp stack_name(stack) do
    Map.get(stack, :name, Map.get(stack, "name", "unnamed-stack"))
  end

  defp description(stack, project) do
    case Map.get(stack, :description, Map.get(stack, "description")) do
      d when is_binary(d) and d != "" -> d
      _ -> "Container stack #{project}, compiled by stapeln."
    end
  end

  # Treats "" as absent: an empty string is how a form posts a field the user
  # left blank, and "AUTHOR = " in a manifest is no better than "{{AUTHOR}}".
  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(v) when is_binary(v), do: String.trim(v) != ""
  defp present?(_), do: true

  defp opt(opts, key, default) do
    if present?(opts[key]), do: to_string(opts[key]), else: default
  end

  # ---------------------------------------------------------------------------
  # Rendering
  # ---------------------------------------------------------------------------

  defp render_all(tokens) do
    Enum.reduce_while(@bundle_templates, {:ok, %{}}, fn name, {:ok, acc} ->
      case render(name, tokens) do
        {:ok, content} -> {:cont, {:ok, Map.put(acc, name, content)}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp render(name, tokens) do
    path = Path.join(template_dir(), name)

    with {:ok, raw} <- read_template(path, name) do
      content =
        Enum.reduce(tokens, raw, fn {token, value}, acc ->
          String.replace(acc, "{{#{token}}}", value)
        end)

      {:ok, assert_no_placeholders!(content, name)}
    end
  end

  defp read_template(path, name) do
    case File.read(path) do
      {:ok, raw} ->
        {:ok, raw}

      {:error, reason} ->
        {:error,
         "cannot read bundle template #{name} at #{path}: #{:file.format_error(reason)}"}
    end
  end

  # ---------------------------------------------------------------------------
  # The design file -- what makes the bundle round-trippable
  # ---------------------------------------------------------------------------

  # The canvas is the source of truth, not the generated files, so the design
  # travels inside the bundle. ST4's round-trip gate reads this back and asserts
  # design == raise(lower(design)).
  defp design_json(stack) do
    payload = %{
      "schema" => "stapeln.design/v1",
      "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "name" => stack_name(stack),
      "design" => Map.get(stack, :design, Map.get(stack, "design")),
      "services" => Codegen.normalise_services(stack)
    }

    Jason.encode!(payload, pretty: true) <> "\n"
  end
end
