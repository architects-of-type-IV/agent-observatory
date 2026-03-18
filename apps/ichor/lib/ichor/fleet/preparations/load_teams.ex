defmodule Ichor.Fleet.Preparations.LoadTeams do
  @moduledoc """
  Compatibility wrapper for fleet team view preparation.
  """
  use Ash.Resource.Preparation

  @impl true
  def prepare(query, opts, context) do
    Ichor.Fleet.Views.Preparations.LoadTeams.prepare(query, opts, context)
  end
end
