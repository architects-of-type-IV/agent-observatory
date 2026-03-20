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

  @sweep_interval_seconds 120

  @spec schedule(non_neg_integer()) :: {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  def schedule(delay_seconds \\ @sweep_interval_seconds) when is_integer(delay_seconds) do
    %{}
    |> new(schedule_in: delay_seconds)
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    active_runs = length(Runner.list_all(:mes))
    Signals.emit(:mes_maintenance_init, %{monitored: active_runs})

    result =
      try do
        Spawn.cleanup_orphaned_teams()
        :ok
      rescue
        error ->
          reason = Exception.message(error)
          Signals.emit(:mes_maintenance_error, %{run_id: "sweep", reason: reason})
          {:error, reason}
      end

    unless oban_inline_testing?() do
      _ = schedule()
    end

    result
  end

  defp oban_inline_testing? do
    Application.get_env(:ichor, Oban, [])
    |> Keyword.get(:testing)
    |> Kernel.==(:inline)
  end
end
