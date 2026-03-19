defmodule Ichor.Signals.Domain do
  @moduledoc """
  Ash Domain for the signal system. Owns the Event resource.
  Separated from the public Ichor.Signals facade which lives in ichor_contracts.
  """

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource(Ichor.Signals.Event)
  end
end
