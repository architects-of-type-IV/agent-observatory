defmodule Ichor.Projector.Supervisor do
  @moduledoc """
  DynamicSupervisor for signal processes.

  Each signal process is started on demand when the first event for its
  `{signal_module, key}` arrives. Crashed processes are restarted independently.
  """

  use DynamicSupervisor

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(_opts) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
