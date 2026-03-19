defmodule Ichor.Gateway.Types.HITLAction do
  @moduledoc """
  Ash enum type for HITL operator action kinds.

  Each value maps to a command an operator can issue through the HITL controller.
  """

  use Ash.Type.Enum,
    values: [:pause, :unpause, :rewrite, :inject]
end
