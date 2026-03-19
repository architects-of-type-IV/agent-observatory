defmodule Ichor.Archon.TeamWatchdog do
  @moduledoc """
  Signal-driven team lifecycle monitor. No timers, no polling.
  Reacts to fleet and run signals to detect unexpected deaths,
  archive runs, reset jobs, and notify operator.

  Pure decision logic in Reactions module; this GenServer dispatches only.
  """

  use GenServer

  alias Ichor.Archon.TeamWatchdog.Reactions
  alias Ichor.Dag.{Job, Run}
  alias Ichor.Fleet.FleetSupervisor
  alias Ichor.Signals
  alias Ichor.Signals.Message

  @inbox_dir Path.expand("~/.claude/inbox")

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
    {actions, new_state} = Reactions.react(name, data, state)
    Enum.each(actions, &dispatch/1)
    {:noreply, new_state}
  end

  def handle_info(_, state), do: {:noreply, state}

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
