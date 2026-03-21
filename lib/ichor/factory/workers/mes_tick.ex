defmodule Ichor.Factory.Workers.MesTick do
  @moduledoc "Oban cron worker that spawns MES planning runs on a 1-minute schedule."
  use Oban.Worker, queue: :scheduled, max_attempts: 1, unique: [period: 50]

  alias Ichor.Factory.{Runner, RunRef}
  alias Ichor.Signals

  @max_concurrent 1
  @pause_flag Path.join(File.cwd!(), "tmp/mes_paused")

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    all = Runner.list_all(:mes)
    active = count_active(all)

    cond do
      File.exists?(@pause_flag) ->
        Signals.emit(:mes_tick, %{paused: true})

      active < @max_concurrent ->
        Signals.emit(:mes_tick, %{active_runs: active, total_runs: length(all)})
        spawn_run()

      true ->
        Signals.emit(:mes_tick, %{active_runs: active, total_runs: length(all)})
        Signals.emit(:mes_cycle_skipped, %{active_runs: active})
    end

    :ok
  end

  defp count_active(runs) do
    Enum.count(runs, fn {_run_id, pid} ->
      try do
        not GenServer.call(pid, :deadline_passed?, 1_000)
      catch
        :exit, _ -> false
      end
    end)
  end

  defp spawn_run do
    run_id = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    team_name = RunRef.session_name(RunRef.new(:mes, run_id))

    case Runner.start(:mes, run_id: run_id, team_name: team_name) do
      {:ok, _pid} ->
        Signals.emit(:mes_cycle_started, %{run_id: run_id, team_name: team_name})

      {:error, reason} ->
        Signals.emit(:mes_cycle_failed, %{run_id: run_id, reason: inspect(reason)})
    end
  end
end
