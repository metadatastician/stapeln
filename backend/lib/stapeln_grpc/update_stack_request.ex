# SPDX-License-Identifier: MPL-2.0
defmodule StapelnGrpc.UpdateStackRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3

  field(:id, 1, type: :string)
  field(:name, 2, type: :string)
  field(:description, 3, type: :string)
  field(:services, 4, repeated: true, type: StapelnGrpc.ServicePayload)
end
