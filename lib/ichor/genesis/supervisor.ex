defmodule Ichor.Genesis.Supervisor do
  @moduledoc """
  Top-level supervisor for the Genesis pipeline subsystem.

  Supervision tree:

      Genesis.Supervisor
        +-- DynamicSupervisor (Ichor.Genesis.RunSupervisor)  # one child per mode run
  """

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {DynamicSupervisor, name: Ichor.Genesis.RunSupervisor, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
