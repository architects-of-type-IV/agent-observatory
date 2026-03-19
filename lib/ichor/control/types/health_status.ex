defmodule Ichor.Control.Types.HealthStatus do
  @moduledoc """
  Ash enum type for agent and team health status.

  - `:healthy`  -- all checks passing
  - `:warning`  -- degraded but operational
  - `:critical` -- failing, intervention required
  - `:unknown`  -- health not yet assessed
  """

  use Ash.Type.Enum, values: [:healthy, :warning, :critical, :unknown]
end
