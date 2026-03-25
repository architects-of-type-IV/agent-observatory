defmodule Ichor.Factory.MesScheduler do
  @moduledoc "MES scheduler control API. The actual tick runs via Oban cron (Workers.MesTick)."

  alias Ichor.Events
  alias Ichor.Events.Event
  alias Ichor.Factory.Runner

  @pause_flag Path.join(File.cwd!(), "tmp/mes_paused")

  @doc "Pauses the MES scheduler by writing a flag file to disk."
  @spec pause() :: :ok
  def pause do
    File.mkdir_p!(Path.dirname(@pause_flag))
    File.write!(@pause_flag, "")

    Events.emit(Event.new("mes.scheduler.paused", nil, %{}))

    :ok
  end

  @doc "Resumes the MES scheduler by removing the flag file from disk."
  @spec resume() :: :ok
  def resume do
    File.rm(@pause_flag)

    Events.emit(Event.new("mes.scheduler.resumed", nil, %{}))

    :ok
  end

  @doc "Returns true if the MES scheduler is currently paused."
  @spec paused?() :: boolean()
  def paused?, do: File.exists?(@pause_flag)

  @doc "Returns current scheduler status including active and total run counts."
  @spec status() :: map()
  def status do
    all = Runner.list_all(:mes)

    active_count =
      Enum.count(all, fn {_run_id, pid} ->
        not Runner.deadline_passed?(pid)
      end)

    %{
      active_runs: active_count,
      total_runs: length(all),
      next_tick_in: 60_000,
      paused: paused?()
    }
  end
end
