defmodule Ichor.Events do
  use Ash.Domain, validate_config_inclusion?: false
  @moduledoc false

  resources do
    resource(Ichor.Events.Event)
    resource(Ichor.Events.Session)
  end

  @spec list_events(keyword()) :: [Ichor.Events.Event.t()]
  def list_events(opts \\ []) do
    Ichor.Events.Event.read!(opts)
  end
end
