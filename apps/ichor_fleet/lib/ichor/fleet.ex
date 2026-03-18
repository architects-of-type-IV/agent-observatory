defmodule Ichor.Fleet do
  use Ash.Domain
  @moduledoc false

  resources do
    resource(Ichor.Fleet.Agent)
    resource(Ichor.Fleet.Team)
  end
end
