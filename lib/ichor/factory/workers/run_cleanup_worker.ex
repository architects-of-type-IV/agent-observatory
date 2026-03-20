defmodule Ichor.Factory.Workers.RunCleanupWorker do
  @moduledoc """
  Cleans up MES team runtime state after a run exits.
  """

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 5,
    unique: [period: 60, fields: [:worker, :args], keys: [:run_id]]

  alias Ichor.Factory.Spawn
  alias Ichor.Infrastructure.FleetSupervisor
  alias Ichor.Infrastructure.Tmux
  alias Ichor.Signals

  @spec enqueue(String.t(), keyword()) :: {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  def enqueue(run_id, opts \\ []) when is_binary(run_id) do
    trigger = Keyword.get(opts, :trigger, "runner")

    %{run_id: run_id, trigger: trigger}
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"run_id" => run_id} = args}) do
    session = "mes-" <> run_id
    trigger = Map.get(args, "trigger", "worker")

    try do
      if trigger == "completed" do
        FleetSupervisor.disband_team(session)
        Spawn.kill_session(session)
        Signals.emit(:mes_janitor_cleaned, %{run_id: run_id, trigger: trigger})
      else
        if Tmux.available?(session) do
          Signals.emit(:mes_janitor_skipped, %{run_id: run_id, reason: "tmux_alive"})
        else
          FleetSupervisor.disband_team(session)
          Spawn.kill_session(session)
          Signals.emit(:mes_janitor_cleaned, %{run_id: run_id, trigger: trigger})
        end
      end

      :ok
    rescue
      error ->
        reason = Exception.message(error)
        Signals.emit(:mes_janitor_error, %{run_id: run_id, reason: reason})
        {:error, reason}
    end
  end
end
