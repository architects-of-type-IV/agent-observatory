defmodule Ichor.Factory.Workers.OrphanSweepWorker do
  @moduledoc """
  Periodically sweeps orphaned MES teams and tmux sessions.
  """

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 5,
    unique: [period: 90, fields: [:worker]]

  alias Ichor.Factory.{Runner, Spawn}
  alias Ichor.Signals

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    active_runs = length(Runner.list_all(:mes))
    Signals.emit(:mes_maintenance_init, %{monitored: active_runs})

    try do
      Spawn.cleanup_orphaned_teams()
      :ok
    rescue
      error ->
        reason = Exception.message(error)
        Signals.emit(:mes_maintenance_error, %{run_id: "sweep", reason: reason})
        {:error, reason}
    end
  end
end
