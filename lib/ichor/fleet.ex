defmodule Ichor.Fleet do
  use Ash.Domain

  resources do
    resource Ichor.Fleet.Agent
    resource Ichor.Fleet.Team
  end
end
