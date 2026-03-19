defmodule Ichor.Fleet.Preparations.LoadTeams do
  @moduledoc """
  Compatibility wrapper for fleet team view preparation.
  """
  use Ash.Resource.Preparation

  alias Ichor.Fleet.Views.Preparations.LoadTeams, as: LoadTeamsImpl

  @impl true
  def prepare(query, opts, context) do
    LoadTeamsImpl.prepare(query, opts, context)
  end
end
