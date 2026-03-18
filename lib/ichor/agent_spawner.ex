defmodule Ichor.AgentSpawner do
  @moduledoc """
  Compatibility facade over the fleet lifecycle layer.

  External callers keep using `AgentSpawner`, while runtime orchestration now
  lives under `Ichor.Fleet.Lifecycle`.
  """

  alias Ichor.Fleet.Lifecycle.AgentLaunch

  @type spawn_opts :: AgentLaunch.launch_opts()

  @spec init_counter() :: :ok
  defdelegate init_counter(), to: AgentLaunch

  @spec spawn_agent(spawn_opts()) :: {:ok, map()} | {:error, term()}
  defdelegate spawn_agent(opts), to: AgentLaunch, as: :spawn

  @doc false
  @spec spawn_local(spawn_opts()) :: {:ok, map()} | {:error, term()}
  defdelegate spawn_local(opts), to: AgentLaunch

  @spec list_spawned() :: [String.t()]
  defdelegate list_spawned(), to: AgentLaunch

  @spec spawned_session?(String.t()) :: boolean()
  defdelegate spawned_session?(session), to: AgentLaunch

  @spec stop_agent(String.t()) :: :ok | {:error, term()}
  defdelegate stop_agent(agent_id), to: AgentLaunch, as: :stop
end
