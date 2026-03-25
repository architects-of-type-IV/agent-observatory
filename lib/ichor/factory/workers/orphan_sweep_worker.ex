defmodule Ichor.Factory.Workers.OrphanSweepWorker do
  @moduledoc """
  Periodically sweeps orphaned MES teams and tmux sessions.
  """

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 5,
    unique: [period: 90, fields: [:worker]]

  alias Ichor.Events
  alias Ichor.Events.Event
  alias Ichor.Factory.{Runner, Spawn}

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    active_runs = length(Runner.list_all(:mes))

    Events.emit(
      Event.new(
        "mes.maintenance.init",
        nil,
        %{monitored: active_runs}
      )
    )

    try do
      Spawn.cleanup_orphaned_teams()
      :ok
    rescue
      error ->
        reason = Exception.message(error)

        Events.emit(
          Event.new(
            "mes.maintenance.error",
            "sweep",
            %{run_id: "sweep", reason: reason}
          )
        )

        {:error, reason}
    end
  end
end
