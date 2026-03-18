defmodule Ichor.Events do
  use Ash.Domain
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
