defmodule Ichor.Fleet.Preparations.LoadAgents do
  @moduledoc """
  Compatibility wrapper for fleet agent view preparation.
  """
  use Ash.Resource.Preparation

  @impl true
  def prepare(query, opts, context) do
    Ichor.Fleet.Views.Preparations.LoadAgents.prepare(query, opts, context)
  end
end
