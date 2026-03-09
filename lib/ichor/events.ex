defmodule Ichor.Events do
  use Ash.Domain

  resources do
    resource(Ichor.Events.Event)
    resource(Ichor.Events.Session)
  end
end
