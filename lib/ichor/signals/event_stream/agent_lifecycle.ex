defmodule Ichor.Signals.EventStream.AgentLifecycle do
  @moduledoc """
  Fleet mutations triggered by hook events. Creates, terminates, and manages
  agent processes in response to event stream data.

  All functions here represent what a given event means for the fleet --
  resolving/spawning AgentProcess entries, disbanding teams, and handling
  team lifecycle tool calls.
  """

  require Logger

  alias Ichor.Infrastructure.{AgentProcess, FleetSupervisor, TeamSupervisor}

  @doc """
  Resolve or create an AgentProcess for the given session_id and event.

  Returns the canonical agent id to use for subsequent operations.
  """
  @spec resolve_or_create_agent(String.t(), map()) :: String.t()
  def resolve_or_create_agent(session_id, event) do
    cond do
      AgentProcess.alive?(session_id) ->
        session_id

      match = find_agent_by_tmux(event.tmux_session) ->
        match

      true ->
        spawn_new_agent(session_id, event)
    end
  rescue
    _ -> session_id
  end

  @doc "Look up an existing agent by its tmux session name. Returns agent id or nil."
  @spec find_agent_by_tmux(String.t() | nil) :: String.t() | nil
  def find_agent_by_tmux(nil), do: nil
  def find_agent_by_tmux(""), do: nil

  def find_agent_by_tmux(tmux_session) do
    AgentProcess.list_all()
    |> Enum.find_value(fn {id, meta} ->
      target = meta[:tmux_target] || ""
      session = meta[:tmux_session] || ""

      if session == tmux_session or String.starts_with?(target, tmux_session <> ":") do
        id
      end
    end)
  end

  @doc "Stop the AgentProcess for the given session_id, if one exists."
  @spec terminate_agent_process(String.t()) :: :ok
  def terminate_agent_process(session_id) do
    case AgentProcess.lookup(session_id) do
      {pid, _meta} -> terminate_or_stop(session_id, pid)
      nil -> :ok
    end
  end

  @doc "Terminate via FleetSupervisor; fall back to GenServer.stop if not found."
  @spec terminate_or_stop(String.t(), pid()) :: :ok
  def terminate_or_stop(session_id, pid) do
    case FleetSupervisor.terminate_agent(session_id) do
      :ok ->
        :ok

      {:error, :not_found} ->
        try do
          GenServer.stop(pid, :normal)
        catch
          :exit, _ -> :ok
        end
    end
  end

  @doc "Ensure a TeamSupervisor exists for `team_name`, creating one if needed."
  @spec ensure_team_supervisor(String.t()) :: :ok
  def ensure_team_supervisor(team_name) do
    unless TeamSupervisor.exists?(team_name) do
      case FleetSupervisor.create_team(name: team_name) do
        {:ok, _pid} ->
          :ok

        {:error, :already_exists} ->
          :ok

        {:error, reason} ->
          Logger.debug(
            "[Signals.EventStream] Could not create TeamSupervisor for #{team_name}: #{inspect(reason)}"
          )

          :ok
      end
    end
  rescue
    _ -> :ok
  end

  @doc "Handle a TeamCreate tool input map by ensuring the team supervisor exists."
  @spec handle_team_create(map()) :: :ok
  def handle_team_create(input) do
    if team_name = input["team_name"] do
      ensure_team_supervisor(team_name)
    end

    :ok
  end

  @doc "Handle a TeamDelete tool input map by disbanding the team."
  @spec handle_team_delete(map()) :: :ok
  def handle_team_delete(input) do
    if team_name = input["team_name"] do
      FleetSupervisor.disband_team(team_name)
    end

    :ok
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp spawn_new_agent(session_id, event) do
    tmux_session = if event.tmux_session != "", do: event.tmux_session, else: nil

    opts = [
      id: session_id,
      role: :worker,
      backend: if(tmux_session, do: %{type: :tmux, session: tmux_session}, else: nil),
      metadata: %{
        cwd: event.cwd,
        model: event.model_name,
        os_pid: event.os_pid,
        name: session_id
      }
    ]

    case FleetSupervisor.spawn_agent(opts) do
      {:ok, _pid} -> session_id
      {:error, {:already_started, _}} -> session_id
      {:error, _reason} -> session_id
    end
  end
end
