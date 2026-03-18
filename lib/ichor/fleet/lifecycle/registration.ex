defmodule Ichor.Fleet.Lifecycle.Registration do
  @moduledoc """
  Shared process registration for tmux-backed agents and teams.
  """

  require Logger

  alias Ichor.Fleet.AgentProcess
  alias Ichor.Fleet.FleetSupervisor
  alias Ichor.Fleet.Lifecycle.AgentSpec
  alias Ichor.Fleet.TeamSupervisor
  alias Ichor.Fleet.TmuxHelpers

  @spec ensure_team(String.t()) :: :ok | {:error, term()}
  def ensure_team(name) do
    case FleetSupervisor.create_team(name: name) do
      {:ok, _pid} -> :ok
      {:error, :already_exists} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec register(AgentSpec.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def register(%AgentSpec{} = spec, tmux_target) do
    process_opts = [
      id: spec.agent_id,
      role: TmuxHelpers.capability_to_role(spec.capability || "builder"),
      team: spec.team_name,
      liveness_poll: true,
      backend: %{type: :tmux, session: tmux_target},
      capabilities: TmuxHelpers.capabilities_for(spec.capability || "builder"),
      metadata:
        Map.put(spec.metadata, :cwd, spec.cwd) |> Map.put_new(:model, spec.model || "sonnet")
    ]

    do_register(process_opts, spec)
  end

  defp do_register(process_opts, %AgentSpec{team_name: nil} = spec) do
    case FleetSupervisor.spawn_agent(process_opts) do
      {:ok, _pid} ->
        {:ok,
         %{
           agent_id: spec.agent_id,
           session_name: "#{spec.session}:#{spec.window_name}",
           name: spec.name,
           cwd: spec.cwd,
           node: Node.self()
         }}

      {:error, {:already_started, pid}} ->
        {:ok,
         %{
           agent_id: spec.agent_id,
           session_name: "#{spec.session}:#{spec.window_name}",
           pid: inspect(pid),
           name: spec.name,
           cwd: spec.cwd,
           node: Node.self()
         }}

      {:error, reason} ->
        Logger.warning(
          "[Lifecycle.Registration] standalone registration failed: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp do_register(process_opts, %AgentSpec{team_name: team_name} = spec) do
    with :ok <- ensure_team(team_name) do
      case TeamSupervisor.spawn_member(team_name, process_opts) do
        {:ok, _pid} ->
          {:ok,
           %{
             agent_id: spec.agent_id,
             session_name: "#{spec.session}:#{spec.window_name}",
             name: spec.name,
             cwd: spec.cwd,
             node: Node.self()
           }}

        {:error, {:already_started, pid}} ->
          {:ok,
           %{
             agent_id: spec.agent_id,
             session_name: "#{spec.session}:#{spec.window_name}",
             pid: inspect(pid),
             name: spec.name,
             cwd: spec.cwd,
             node: Node.self()
           }}

        {:error, reason} ->
          Logger.warning("[Lifecycle.Registration] team registration failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @spec resolve_tmux_target(String.t()) :: String.t() | nil
  def resolve_tmux_target(agent_id) do
    case AgentProcess.lookup(agent_id) do
      {_pid, %{tmux_target: target}} when is_binary(target) -> target
      _ -> nil
    end
  end

  @spec terminate(String.t()) :: :ok | {:error, :not_found}
  def terminate(agent_id) do
    case AgentProcess.alive?(agent_id) do
      false ->
        :ok

      true ->
        state = AgentProcess.get_state(agent_id)

        case state.team do
          nil -> FleetSupervisor.terminate_agent(agent_id)
          team -> TeamSupervisor.terminate_member(team, agent_id)
        end
    end
  end
end
