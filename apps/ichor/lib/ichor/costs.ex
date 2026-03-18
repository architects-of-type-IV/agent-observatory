defmodule Ichor.Costs do
  use Ash.Domain
  @moduledoc false

  resources do
    resource(Ichor.Costs.TokenUsage)
  end
end
