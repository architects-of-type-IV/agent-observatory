defmodule Ichor.Projector.CleanupDispatcher do
  @moduledoc """
  Projector for cleanup signals: dispatches Oban worker jobs for run and session cleanup.

  Subscribes to the `:cleanup` signal category and reacts to cleanup signals
  emitted by TeamWatchdog by inserting the appropriate Oban worker jobs:

    - `:run_cleanup_needed` with `action: :archive`      -> ArchiveRunWorker
    - `:run_cleanup_needed` with `action: :reset_tasks`  -> ResetRunTasksWorker
    - `:session_cleanup_needed` with `action: :disband`  -> DisbandTeamWorker
    - `:session_cleanup_needed` with `action: :kill`     -> KillSessionWorker

  All Oban inserts use a 60-second deduplication window to avoid duplicate jobs
  for the same resource.
  """

  use GenServer

  require Logger

  alias Ichor.Factory.Workers.ArchiveRunWorker
  alias Ichor.Factory.Workers.ResetRunTasksWorker
  alias Ichor.Infrastructure.Workers.DisbandTeamWorker
  alias Ichor.Infrastructure.Workers.KillSessionWorker
  alias Ichor.Signals
  alias Ichor.Signals.Message

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    Signals.subscribe(:cleanup)
    {:ok, %{}}
  end

  @impl true
  def handle_info(
        %Message{name: :run_cleanup_needed, data: %{run_id: run_id, action: :archive}},
        state
      ) do
    insert_job(%{"run_id" => run_id}, ArchiveRunWorker, period: 60, keys: [:run_id])
    {:noreply, state}
  end

  @impl true
  def handle_info(
        %Message{name: :run_cleanup_needed, data: %{run_id: run_id, action: :reset_tasks}},
        state
      ) do
    insert_job(%{"run_id" => run_id}, ResetRunTasksWorker, period: 60, keys: [:run_id])
    {:noreply, state}
  end

  @impl true
  def handle_info(
        %Message{name: :session_cleanup_needed, data: %{session: session, action: :disband}},
        state
      ) do
    insert_job(%{"session" => session}, DisbandTeamWorker, period: 60, keys: [:session])
    {:noreply, state}
  end

  @impl true
  def handle_info(
        %Message{name: :session_cleanup_needed, data: %{session: session, action: :kill}},
        state
      ) do
    insert_job(%{"session" => session}, KillSessionWorker, period: 60, keys: [:session])
    {:noreply, state}
  end

  @impl true
  def handle_info(%Message{}, state), do: {:noreply, state}

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  defp insert_job(args, worker, unique_opts) do
    case args |> worker.new(unique: unique_opts) |> Oban.insert() do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "[CleanupDispatcher] Failed to insert #{inspect(worker)} job #{inspect(args)}: #{inspect(reason)}"
        )
    end
  end
end
