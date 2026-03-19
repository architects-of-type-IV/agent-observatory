defmodule Ichor.Fleet.Preparations.LoadAgents do
  @moduledoc """
  Compatibility wrapper for fleet agent view preparation.
  """
  use Ash.Resource.Preparation

  alias Ichor.Fleet.Views.Preparations.LoadAgents, as: LoadAgentsImpl

  @impl true
  def prepare(query, opts, context) do
    LoadAgentsImpl.prepare(query, opts, context)
  end
end
