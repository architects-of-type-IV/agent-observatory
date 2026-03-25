defmodule Ichor.Factory.Workers.MesTick do
  @moduledoc "Oban cron worker that spawns MES planning runs on a 1-minute schedule."
  use Oban.Worker, queue: :scheduled, max_attempts: 1, unique: [period: 50]

  alias Ichor.Events
  alias Ichor.Events.Event
  alias Ichor.Factory.{Runner, RunRef}

  @max_concurrent 1
  @pause_flag Path.join(File.cwd!(), "tmp/mes_paused")

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    all = Runner.list_all(:mes)
    active = count_active(all)

    cond do
      File.exists?(@pause_flag) ->
        Events.emit(Event.new("mes.tick", nil, %{paused: true}, %{legacy_name: :mes_tick}))

      active < @max_concurrent ->
        Events.emit(
          Event.new(
            "mes.tick",
            nil,
            %{active_runs: active, total_runs: length(all)},
            %{legacy_name: :mes_tick}
          )
        )

        spawn_run()

      true ->
        Events.emit(
          Event.new(
            "mes.tick",
            nil,
            %{active_runs: active, total_runs: length(all)},
            %{legacy_name: :mes_tick}
          )
        )

        Events.emit(
          Event.new(
            "mes.cycle.skipped",
            nil,
            %{active_runs: active},
            %{legacy_name: :mes_cycle_skipped}
          )
        )
    end

    :ok
  end

  defp count_active(runs) do
    Enum.count(runs, fn {_run_id, pid} ->
      not Runner.deadline_passed?(pid)
    end)
  end

  defp spawn_run do
    run_id = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    team_name = RunRef.session_name(RunRef.new(:mes, run_id))

    case Runner.start(:mes, run_id: run_id, team_name: team_name) do
      {:ok, _pid} ->
        Events.emit(
          Event.new(
            "mes.cycle.started",
            run_id,
            %{run_id: run_id, team_name: team_name},
            %{legacy_name: :mes_cycle_started}
          )
        )

      {:error, reason} ->
        Events.emit(
          Event.new(
            "mes.cycle.failed",
            run_id,
            %{run_id: run_id, reason: inspect(reason)},
            %{legacy_name: :mes_cycle_failed}
          )
        )
    end
  end
end
