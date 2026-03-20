defmodule Ichor.Archon.TeamWatchdog do
  @moduledoc """
  Signal-driven team lifecycle monitor. No timers, no polling.
  Reacts to fleet and run signals to detect unexpected deaths,
  archive runs, reset jobs, and notify operator.
  """

  use GenServer

  alias Ichor.Control.FleetSupervisor
  alias Ichor.Projects.{Job, Run}
  alias Ichor.Signals
  alias Ichor.Signals.Message

  @inbox_dir Path.expand("~/.claude/inbox")

  @type action ::
          {:archive_run, String.t()}
          | {:reset_jobs, String.t()}
          | {:notify_operator, String.t()}
          | {:disband_team, String.t()}
          | :noop

  @type state :: %{completed_runs: MapSet.t()}

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    Signals.subscribe(:fleet)
    Signals.subscribe(:dag)
    Signals.subscribe(:genesis)
    Signals.subscribe(:monitoring)
    {:ok, %{completed_runs: MapSet.new()}}
  end

  @impl true
  def handle_info(%Message{name: name, data: data}, state) do
    {actions, new_state} = react(name, data, state)
    Enum.each(actions, &dispatch/1)
    {:noreply, new_state}
  end

  def handle_info(_, state), do: {:noreply, state}

  # Clean completion -- record it so we don't false-positive on disband
  defp react(:dag_run_completed, %{run_id: run_id}, state) do
    {[:noop], %{state | completed_runs: MapSet.put(state.completed_runs, run_id)}}
  end

  # DAG tmux session died -- RunProcess detected it and emitted this signal
  defp react(:dag_tmux_gone, %{run_id: run_id, session: session}, state) do
    case MapSet.member?(state.completed_runs, run_id) do
      true -> {[:noop], state}
      false -> {dag_cleanup_actions(run_id, session, "tmux session died"), state}
    end
  end

  # Fleet team disbanded -- check if it was a DAG team that didn't complete
  defp react(:team_disbanded, %{team_name: "dag-" <> _ = session}, state) do
    case Enum.any?(state.completed_runs, &String.contains?(session, &1)) do
      true -> {[:noop], state}
      false -> {[{:notify_operator, "DAG team #{session} disbanded without completion."}], state}
    end
  end

  # Genesis tmux session died
  defp react(:genesis_tmux_gone, %{session: session}, state) do
    {[
       {:disband_team, session},
       {:notify_operator, "Genesis session #{session} died. Fleet disbanded."}
     ], state}
  end

  # Agent stopped -- if it's a coordinator/lead, the team is headless
  defp react(:agent_stopped, %{session_id: id, role: role}, state)
       when role in [:coordinator, :lead] do
    case extract_dag_session(id) do
      nil ->
        {[:noop], state}

      session ->
        {[{:notify_operator, "DAG #{role} #{id} stopped. Team #{session} may be headless."}],
         state}
    end
  end

  defp react(_signal, _data, state), do: {[:noop], state}

  defp dag_cleanup_actions(run_id, session, reason) do
    [
      {:archive_run, run_id},
      {:reset_jobs, run_id},
      {:disband_team, session},
      {:notify_operator, "DAG run #{run_id} cleaned up: #{reason}. Jobs reset."}
    ]
  end

  defp extract_dag_session("dag-" <> _ = id) do
    case String.split(id, "-", parts: 3) do
      ["dag", hex, _role] -> "dag-#{hex}"
      _ -> nil
    end
  end

  defp extract_dag_session(_), do: nil

  defp dispatch(:noop), do: :ok

  defp dispatch({:archive_run, run_id}) do
    case Run.get(run_id) do
      {:ok, %{status: :active} = run} ->
        Run.archive(run)
        Signals.emit(:dag_run_archived, %{run_id: run_id, label: run.label, reason: "watchdog"})

      _ ->
        :ok
    end
  end

  defp dispatch({:reset_jobs, run_id}) do
    case Job.by_run(run_id) do
      {:ok, jobs} ->
        jobs
        |> Enum.filter(&(&1.status == :in_progress))
        |> Enum.each(&Job.reset/1)

      _ ->
        :ok
    end
  end

  defp dispatch({:disband_team, session}) do
    FleetSupervisor.disband_team(session)
  end

  defp dispatch({:notify_operator, message}) do
    File.mkdir_p!(@inbox_dir)

    notification = %{
      type: "team_watchdog",
      message: message,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    path = Path.join(@inbox_dir, "watchdog-#{System.unique_integer([:positive])}.json")
    File.write!(path, Jason.encode!(notification))
  end
end
