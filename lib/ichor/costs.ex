defmodule Ichor.Costs do
  use Ash.Domain

  resources do
    resource(Ichor.Costs.TokenUsage)
  end
end
