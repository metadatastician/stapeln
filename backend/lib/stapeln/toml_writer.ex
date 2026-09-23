# SPDX-License-Identifier: MPL-2.0
defmodule Stapeln.TomlWriter do
  @moduledoc """
  A writer for the restricted TOML subset stapeln emits (assumption A6).

  Only quoted strings, decimal integers, booleans, RFC 3339 timestamps carried
  as strings, arrays, inline tables and arrays-of-tables. Sub-tables under an
  array-of-tables element are never emitted: nested data on a `[[part]]` uses
  an inline table. The result is a plain data tree that a later emitter can
  serialise into the deed form unchanged, which is the whole reason for the
  restriction.

  ## Strings are rejected, not escaped

  `encode_string/1` raises on a value containing a quote, a backslash or a
  control character rather than escaping it. This is the same decision
  `Stapeln.BundleCodegen` documents for its tokens and for the same reason: a
  value that reaches this writer also reaches YAML, Nickel and shell emitters
  with four incompatible escaping rules, so one escaping implementation would
  have to be correct in four grammars at once. Rejecting is the only rule that
  is right everywhere.

  Concretely, it is what stops a stack named `A"\\nInjected = true` from
  writing a second key into `[stack]`.

  This module writes TOML. It does not read it: `stack.lock` is decoded by a
  real TOML decoder, so the contract test is not stapeln checking its own
  emitter with its own parser.
  """

  @unsafe ~r/["\\]|[\x00-\x1F\x7F]/

  @doc """
  Encode a bare string as a TOML basic string, including the quotes.

  Raises `ArgumentError` when the value cannot be represented without escaping.
  """
  @spec encode_string(String.t()) :: String.t()
  def encode_string(value) when is_binary(value) do
    if Regex.match?(@unsafe, value) do
      raise ArgumentError,
            "value contains a quote, backslash or control character and cannot be emitted " <>
              "into TOML without escaping: #{inspect(value)}"
    end

    ~s("#{value}")
  end

  @doc """
  Encode a scalar, array or inline table.

  Lists become arrays; maps become inline tables with their keys sorted, so the
  output is deterministic for a given record tree.
  """
  @spec encode_value(term()) :: String.t()
  def encode_value(value) when is_binary(value), do: encode_string(value)
  def encode_value(value) when is_integer(value), do: Integer.to_string(value)
  def encode_value(true), do: "true"
  def encode_value(false), do: "false"

  def encode_value(list) when is_list(list) do
    "[" <> Enum.map_join(list, ", ", &encode_value/1) <> "]"
  end

  def encode_value(map) when is_map(map) do
    body =
      map
      |> Enum.sort_by(fn {key, _} -> to_string(key) end)
      |> Enum.map_join(", ", fn {key, value} ->
        "#{encode_key(key)} = #{encode_value(value)}"
      end)

    "{ " <> body <> " }"
  end

  def encode_value(other) do
    raise ArgumentError, "cannot emit #{inspect(other)} in stapeln's TOML subset"
  end

  @doc """
  A `key = value` line.
  """
  @spec encode_pair(atom() | String.t(), term()) :: String.t()
  def encode_pair(key, value), do: "#{encode_key(key)} = #{encode_value(value)}"

  @doc """
  Encode a key. Bare where TOML allows it, quoted otherwise -- slot ids such as
  `base-image` are bare-legal, but the rule is applied rather than assumed.
  """
  @spec encode_key(atom() | String.t()) :: String.t()
  def encode_key(key) do
    key = to_string(key)

    if Regex.match?(~r/\A[A-Za-z0-9_-]+\z/, key) do
      key
    else
      encode_string(key)
    end
  end
end
