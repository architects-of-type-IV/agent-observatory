defmodule Ichor.Events.Types.SessionStatus do
  @moduledoc """
  Ash enum type for agent session lifecycle status.
  """

  use Ash.Type.Enum, values: [:active, :ended]
end
