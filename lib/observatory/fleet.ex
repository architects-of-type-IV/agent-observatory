defmodule Observatory.Fleet do
  use Ash.Domain

  resources do
    resource Observatory.Fleet.Agent
    resource Observatory.Fleet.Team
  end
end
