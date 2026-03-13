defmodule Ichor.Mes.AgentSupervisor do
  @moduledoc """
  DynamicSupervisor for MES agent processes.

  MES agents are registered here -- NOT under Fleet.TeamSupervisor -- because
  their lifecycle is tied to tmux window liveness, not to RunProcess or team
  lifecycle. When a RunProcess crashes or a team is disbanded, these agents
  survive as long as their tmux windows are alive.

  Each MES AgentProcess monitors its own tmux window via a periodic liveness
  check. When the window dies, the agent self-terminates and is cleaned up.
  """

  use DynamicSupervisor

  alias Ichor.Mes.MesAgentProcess

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec spawn_agent(keyword()) :: DynamicSupervisor.on_start_child()
  def spawn_agent(opts) do
    DynamicSupervisor.start_child(__MODULE__, {MesAgentProcess, opts})
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one, max_restarts: 20, max_seconds: 60)
  end
end
