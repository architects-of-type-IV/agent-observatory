defmodule Ichor.Events do
  use Ash.Domain
  @moduledoc false

  resources do
    resource(Ichor.Events.Event)
    resource(Ichor.Events.Session)
  end
end
