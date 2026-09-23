# SPDX-License-Identifier: MPL-2.0
defmodule Mix.Tasks.Stapeln.Bundle do
  @moduledoc """
  Emit the stapeln bundle, or check an emitted `stack.lock`.

      mix stapeln.bundle --design DESIGN.json --out out/bundle \\
        --author "A" --email "a@example.com" --license MPL-2.0 --owner metadatastician

      mix stapeln.bundle --check out/bundle/stack.lock

  `--check` runs the same structural assertions as the contract test
  (`stack_declaration_test.exs`) against a file on disk, which is how the smoke
  checks a bundle it did not generate in the same process. It decodes the file
  with a real TOML decoder and exits non-zero on the first failure, so it can
  be used as a gate.
  """

  @shortdoc "Emit the stapeln bundle, or check an emitted stack.lock"

  use Mix.Task

  alias Stapeln.{Design, StackLockCheck}

  @switches [
    design: :string,
    out: :string,
    check: :string,
    name: :string,
    author: :string,
    email: :string,
    license: :string,
    owner: :string,
    version: :string,
    repo: :string,
    forge: :string,
    registry: :string
  ]

  @required [:author, :email, :license, :owner]

  @impl Mix.Task
  def run(argv) do
    {opts, _rest, invalid} = OptionParser.parse(argv, strict: @switches)

    unless invalid == [] do
      Mix.raise("unrecognised option(s): #{inspect(Enum.map(invalid, &elem(&1, 0)))}")
    end

    Mix.Task.run("app.start")

    case Keyword.get(opts, :check) do
      nil -> emit(opts)
      path -> check(path)
    end
  end

  # ---------------------------------------------------------------------------
  # --check
  # ---------------------------------------------------------------------------

  defp check(path) do
    contents =
      case File.read(path) do
        {:ok, contents} -> contents
        {:error, reason} -> Mix.raise("cannot read #{path}: #{:file.format_error(reason)}")
      end

    # The design that shipped beside it, when there is one, so design_sha256 is
# checked against real bytes rather than merely well-formed.
design =
  case File.read(Path.join(Path.dirname(path), "stapeln.design.json")) do
    {:ok, bytes} -> bytes
    {:error, _} -> nil
  end

case StackLockCheck.check(contents, design) do
      :ok ->
        Mix.shell().info("#{path}: ok (#{length(Stapeln.Slots.keys())} slot keys, header intact)")

      {:error, reason} ->
        Mix.raise("#{path}: #{reason}")
    end
  end

  # ---------------------------------------------------------------------------
  # emit
  # ---------------------------------------------------------------------------

  defp emit(opts) do
    design_path = Keyword.get(opts, :design) || Mix.raise("--design DESIGN.json is required")
    out = Keyword.get(opts, :out) || Mix.raise("--out DIR is required")

    missing = Enum.reject(@required, &Keyword.has_key?(opts, &1))

    unless missing == [] do
      Mix.raise("missing required option(s): #{Enum.map_join(missing, ", ", &"--#{&1}")}")
    end

    design =
      design_path
      |> File.read!()
      |> Jason.decode!()

    case Design.valid?(design) do
      :ok -> :ok
      {:error, reason} -> Mix.raise("#{design_path}: #{reason}")
    end

    stack = %{
      "name" => Keyword.get(opts, :name, stack_name(design, design_path)),
      "design" => design,
      "services" => Design.derive_services(design)
    }

    bundle_opts =
      opts
      |> Keyword.take([:author, :email, :license, :owner, :version, :repo, :forge, :registry])

    case Stapeln.BundleCodegen.generate(stack, bundle_opts) do
      {:ok, files} ->
        File.mkdir_p!(out)

        Enum.each(files, fn {name, contents} ->
          File.write!(Path.join(out, name), contents)
        end)

        Mix.shell().info("wrote #{map_size(files)} files to #{out}")
        check(Path.join(out, "stack.lock"))

      {:error, reason} ->
        Mix.raise(reason)
    end
  end

  defp stack_name(design, design_path) do
    case get_in(design, ["metadata", "name"]) do
      name when is_binary(name) and name != "" ->
        name

      _ ->
        design_path |> Path.basename() |> Path.rootname()
    end
  end

  # Silence the unused-alias warning: StackDeclaration is referenced only in the
  # moduledoc, but naming it here keeps the task's dependency explicit.
  @doc false
  def declaration_module, do: StackDeclaration
end
