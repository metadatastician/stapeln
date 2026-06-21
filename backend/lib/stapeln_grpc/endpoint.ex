# SPDX-License-Identifier: MPL-2.0
defmodule StapelnGrpc.Endpoint do
  @moduledoc false
  use GRPC.Endpoint

  run(StapelnGrpc.StackService.Server)
end
