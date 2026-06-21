# SPDX-License-Identifier: MPL-2.0
defmodule StapelnGrpc.StackResponse do
  @moduledoc false
  use Protobuf, syntax: :proto3

  field(:stack, 1, type: StapelnGrpc.StackPayload)
end
