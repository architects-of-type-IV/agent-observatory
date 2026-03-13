defmodule Ichor.Mes do
  @moduledoc """
  Ash Domain: Manufacturing Execution System.

  Continuous manufacturing nervous system that autonomously spawns agent teams
  to research and propose new Ichor subsystems. Completed projects are hot-loaded
  into the running BEAM as standalone Mix projects.
  """

  use Ash.Domain

  resources do
    resource(Ichor.Mes.Project)
  end
end
