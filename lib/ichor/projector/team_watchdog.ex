defmodule Ichor.Projector.TeamWatchdog do
  @moduledoc """
  Signal-driven team lifecycle monitor. No timers, no polling.
  Reacts to universal run signals and fleet events to detect unexpected deaths,
  archive runs, reset pipeline tasks, and notify operator.
  """

  use GenServer

  alias Ichor.Operator.Inbox
  alias Ichor.Signals
  alias Ichor.Signals.Message
  alias Ichor.Workshop.AgentId

  @type action ::
          {:archive_run, String.t()}
          | {:reset_tasks, String.t()}
          | {:notify_operator, String.t()}
          | {:disband_team, String.t()}
          | {:kill_session, String.t()}
          | :noop

  @type state :: %{completed_runs: MapSet.t()}

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    Signals.subscribe(:fleet)
    Signals.subscribe(:pipeline)
    Signals.subscribe(:planning)
    Signals.subscribe(:monitoring)
    {:ok, %{completed_runs: MapSet.new()}}
  end

  @impl true
  def handle_info(%Message{name: name, data: data}, state) do
    {actions, new_state} = react(name, data, state)
    Enum.each(actions, &dispatch/1)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(_, state), do: {:noreply, state}

  defp react(:run_complete, %{kind: kind, run_id: run_id, session: session}, state) do
    new_state = %{state | completed_runs: MapSet.put(state.completed_runs, run_id)}
    {cleanup_actions(kind, run_id, session, "completed"), new_state}
  end

  defp react(:run_terminated, %{kind: kind, run_id: run_id, session: session}, state) do
    if MapSet.member?(state.completed_runs, run_id) do
      {[:noop], state}
    else
      {cleanup_actions(kind, run_id, session, "terminated"), state}
    end
  end

  # Fleet team disbanded -- check if it was a pipeline team that didn't complete
  defp react(:team_disbanded, %{team_name: session}, state) do
    case AgentId.parse(session) do
      {:ok, %AgentId{kind: :pipeline}} ->
        if Enum.any?(state.completed_runs, &String.contains?(session, &1)) do
          {[:noop], state}
        else
          {[{:notify_operator, "Pipeline team #{session} disbanded without completion."}], state}
        end

      _ ->
        {[:noop], state}
    end
  end

  # Agent stopped -- if it's a coordinator/lead, the team is headless
  defp react(:agent_stopped, %{session_id: id, role: role}, state)
       when role in [:coordinator, :lead] do
    case AgentId.parse(id) do
      {:ok, %AgentId{kind: :pipeline, run_id: run_id}} ->
        session = "pipeline-#{run_id}"

        {[{:notify_operator, "Pipeline #{role} #{id} stopped. Team #{session} may be headless."}],
         state}

      _ ->
        {[:noop], state}
    end
  end

  defp react(_signal, _data, state), do: {[:noop], state}

  defp cleanup_actions(:pipeline, run_id, session, reason) do
    [
      {:archive_run, run_id},
      {:reset_tasks, run_id},
      {:disband_team, session},
      {:kill_session, session},
      {:notify_operator, "Pipeline run #{run_id} cleaned up: #{reason}. Tasks reset."}
    ]
  end

  defp cleanup_actions(:planning, _run_id, session, reason) do
    [
      {:disband_team, session},
      {:kill_session, session},
      {:notify_operator, "Planning session #{session} cleaned up: #{reason}."}
    ]
  end

  defp cleanup_actions(:mes, _run_id, session, reason) do
    [
      {:disband_team, session},
      {:kill_session, session},
      {:notify_operator, "MES session #{session} cleaned up: #{reason}. Team disbanded."}
    ]
  end

  defp cleanup_actions(_kind, _run_id, session, reason) do
    [
      {:disband_team, session},
      {:kill_session, session},
      {:notify_operator, "Run #{session} cleaned up: #{reason}."}
    ]
  end

  defp dispatch(:noop), do: :ok

  defp dispatch({:archive_run, run_id}) do
    Signals.emit(:run_cleanup_needed, %{run_id: run_id, action: :archive})
  end

  defp dispatch({:reset_tasks, run_id}) do
    Signals.emit(:run_cleanup_needed, %{run_id: run_id, action: :reset_tasks})
  end

  defp dispatch({:disband_team, session}) do
    Signals.emit(:session_cleanup_needed, %{session: session, action: :disband})
  end

  defp dispatch({:kill_session, session}) do
    Signals.emit(:session_cleanup_needed, %{session: session, action: :kill})
  end

  defp dispatch({:notify_operator, message}) do
    Inbox.write(:team_watchdog, %{context: "watchdog", message: message})
  end
end
