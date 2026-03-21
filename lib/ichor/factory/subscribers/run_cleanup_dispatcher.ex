defmodule Ichor.Factory.Subscribers.RunCleanupDispatcher do
  @moduledoc """
  Factory subscriber for run cleanup signals emitted by TeamWatchdog.

  Subscribes to the `:archon` signal category and reacts to
  `:run_cleanup_needed` signals by inserting the appropriate Factory
  Oban worker jobs.  All Oban inserts are domain-local -- no cross-domain
  imports.
  """

  use GenServer

  require Logger

  alias Ichor.Factory.Workers.ArchiveRunWorker
  alias Ichor.Factory.Workers.ResetRunTasksWorker
  alias Ichor.Signals
  alias Ichor.Signals.Message

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    Signals.subscribe(:archon)
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
  def handle_info(%Message{}, state), do: {:noreply, state}

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp insert_job(args, worker, unique_opts) do
    case args |> worker.new(unique: unique_opts) |> Oban.insert() do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "[RunCleanupDispatcher] Failed to insert #{inspect(worker)} job #{inspect(args)}: #{inspect(reason)}"
        )
    end
  end
end
