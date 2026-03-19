defmodule Ichor.Projects.PlanSupervisor do
  @moduledoc """
  Top-level supervisor for the Genesis pipeline subsystem.

  Supervision tree:

      Genesis.Supervisor
        +-- DynamicSupervisor (Ichor.Projects.PlanRunSupervisor)  # one child per mode run
  """

  use Supervisor

  @doc false
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {DynamicSupervisor, name: Ichor.Projects.PlanRunSupervisor, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
