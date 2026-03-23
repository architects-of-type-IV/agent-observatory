defmodule Ichor.Fleet.Supervisor do
  @moduledoc """
  Fleet supervision tree.

  Registry + DynamicSupervisor for sessions.
  """

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {Registry, keys: :unique, name: Ichor.Fleet.Registry},
      {DynamicSupervisor, name: Ichor.Fleet.SessionSupervisor, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
