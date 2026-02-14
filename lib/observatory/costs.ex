defmodule Observatory.Costs do
  use Ash.Domain

  resources do
    resource Observatory.Costs.TokenUsage
  end
end
