defmodule Observatory.Events do
  use Ash.Domain

  resources do
    resource Observatory.Events.Event
    resource Observatory.Events.Session
  end
end
