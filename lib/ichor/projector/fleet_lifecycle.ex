defmodule Ichor.Projector.FleetLifecycle do
  @moduledoc """
  Projector for fleet lifecycle events: session start/end and team create/delete.

  Subscribes to the `:fleet` signal category and reacts to lifecycle signals
  by performing the corresponding Infrastructure-side mutations:

    - `:session_started`       -> spawn AgentProcess if not already alive
    - `:session_ended`         -> mark AgentProcess as ended and terminate it
    - `:team_create_requested` -> create TeamSupervisor via FleetSupervisor
    - `:team_delete_requested` -> disband team via FleetSupervisor

  This is the single point of reaction to Signals-originated lifecycle events
  for fleet infrastructure. No Infrastructure module calls back into Signals.
  """

  use GenServer

  require Logger

  alias Ichor.Infrastructure.AgentProcess
  alias Ichor.Infrastructure.FleetSupervisor
  alias Ichor.Infrastructure.TeamSupervisor
  alias Ichor.Signals
  alias Ichor.Signals.Message

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    Signals.subscribe(:fleet)
    {:ok, %{}}
  end

  @impl true
  def handle_info(
        %Message{name: :session_started, data: %{session_id: session_id} = data},
        state
      ) do
    unless AgentProcess.alive?(session_id), do: spawn_agent(session_id, data)
    {:noreply, state}
  end

  @impl true
  def handle_info(
        %Message{name: :session_ended, data: %{session_id: session_id}},
        state
      ) do
    AgentProcess.update_fields(session_id, %{status: :ended})
    terminate_agent_process(session_id)
    {:noreply, state}
  end

  @impl true
  def handle_info(
        %Message{name: :team_create_requested, data: %{team_name: team_name}},
        state
      ) do
    unless TeamSupervisor.exists?(team_name), do: create_team(team_name)
    {:noreply, state}
  end

  @impl true
  def handle_info(
        %Message{name: :team_delete_requested, data: %{team_name: team_name}},
        state
      ) do
    FleetSupervisor.disband_team(team_name)
    {:noreply, state}
  end

  @impl true
  def handle_info(%Message{}, state), do: {:noreply, state}

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  defp spawn_agent(session_id, data) do
    tmux_session = data |> Map.get(:tmux_session) |> normalize_tmux()

    opts = [
      id: session_id,
      role: :worker,
      backend: if(tmux_session, do: %{type: :tmux, session: tmux_session}, else: nil),
      metadata: %{
        cwd: Map.get(data, :cwd),
        model: Map.get(data, :model),
        os_pid: Map.get(data, :os_pid),
        name: session_id
      }
    ]

    case FleetSupervisor.spawn_agent(opts) do
      {:ok, _pid} ->
        Logger.debug("[FleetLifecycle] Spawned AgentProcess for session #{session_id}")

      {:error, {:already_started, _}} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "[FleetLifecycle] Failed to spawn AgentProcess for #{session_id}: #{inspect(reason)}"
        )
    end
  end

  defp create_team(team_name) do
    case FleetSupervisor.create_team(name: team_name) do
      {:ok, _pid} ->
        Logger.debug("[FleetLifecycle] Created TeamSupervisor for #{team_name}")

      {:error, :already_exists} ->
        :ok

      {:error, reason} ->
        Logger.debug(
          "[FleetLifecycle] Could not create TeamSupervisor for #{team_name}: #{inspect(reason)}"
        )
    end
  end

  defp terminate_agent_process(session_id) do
    case AgentProcess.lookup(session_id) do
      {pid, _meta} -> terminate_or_stop(session_id, pid)
      nil -> :ok
    end
  end

  defp terminate_or_stop(session_id, pid) do
    case FleetSupervisor.terminate_agent(session_id) do
      :ok ->
        :ok

      {:error, :not_found} ->
        catch_exit(fn -> GenServer.stop(pid, :normal) end)
    end
  end

  defp catch_exit(fun) do
    fun.()
  catch
    :exit, _ -> :ok
  end

  defp normalize_tmux(value) when value in [nil, ""], do: nil
  defp normalize_tmux(value), do: value
end
