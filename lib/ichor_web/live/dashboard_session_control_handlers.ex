defmodule IchorWeb.DashboardSessionControlHandlers do
  @moduledoc """
  LiveView event handlers for session control functionality.
  Handles agent shutdown and global instructions push.
  """

  alias Ichor.Events
  alias Ichor.Events.Event
  alias Ichor.Events.EventStream, as: EventRuntime
  alias Ichor.Fleet.AgentProcess
  alias Ichor.Fleet.Supervisor, as: FleetSupervisor
  alias Ichor.Fleet.TeamSupervisor
  alias Ichor.Infrastructure.Tmux
  alias Ichor.Signals.Bus

  import IchorWeb.DashboardToast, only: [push_toast: 3]

  def dispatch("shutdown_agent", p, s), do: handle_shutdown_agent(p, s)

  @doc """
  Handle shutting down an agent session.
  Sends shutdown command, marks ended in registry, and stops the AgentProcess.
  """
  def handle_shutdown_agent(%{"session_id" => session_id}, socket) do
    Bus.send(%{
      from: "operator",
      to: session_id,
      content: "Shutdown requested by dashboard",
      type: :session_control,
      metadata: %{action: "shutdown"},
      transport: :operator
    })

    tmux_killed = kill_tmux_for_agent(session_id)

    beam_stopped =
      case AgentProcess.lookup(session_id) do
        {pid, meta} ->
          result =
            case meta[:team] do
              nil -> FleetSupervisor.terminate_agent(session_id)
              team -> TeamSupervisor.terminate_member(team, session_id)
            end

          # Fallback: if not under a supervisor, stop directly
          if result == {:error, :not_found} do
            try do
              GenServer.stop(pid, :normal)
            catch
              :exit, _ -> :ok
            end
          end

          true

        nil ->
          false
      end

    EventRuntime.tombstone_session(session_id)

    Events.emit(
      Event.new(
        "fleet.agent.stopped",
        session_id,
        %{session_id: session_id, reason: "dashboard_shutdown"}
      )
    )

    short = String.slice(session_id, 0..7)

    details = [
      if(tmux_killed, do: "tmux killed", else: "no tmux"),
      if(beam_stopped, do: "process stopped", else: "no process")
    ]

    socket
    |> Phoenix.Component.assign(:selected_command_agent, nil)
    |> push_toast(:warning, "#{short} -- #{Enum.join(details, " / ")}")
  end

  defp kill_tmux_for_agent(session_id) do
    tmux_target =
      case AgentProcess.lookup(session_id) do
        {_pid, %{channels: %{tmux: name}}} when is_binary(name) -> name
        _ -> session_id
      end

    case Tmux.run_command(["has-session", "-t", tmux_target]) do
      {:ok, _} ->
        Tmux.run_command(["kill-session", "-t", tmux_target])
        true

      _ ->
        false
    end
  end
end
