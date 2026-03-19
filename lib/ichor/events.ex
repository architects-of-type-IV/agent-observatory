defmodule Ichor.Events do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  alias Ichor.Events.Event

  resources do
    resource(Ichor.Events.Event)
    resource(Ichor.Events.Session)
  end

  @spec list_events(keyword()) :: [Event.t()]
  def list_events(opts \\ []) do
    Event.read!(opts)
  end
end
