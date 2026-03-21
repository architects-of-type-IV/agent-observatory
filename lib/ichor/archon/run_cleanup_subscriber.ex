defmodule Ichor.Archon.RunCleanupSubscriber do
  @moduledoc """
  Bridges TeamWatchdog cleanup signals to Oban jobs.

  Subscribes to `:archon` PubSub topic and inserts the appropriate
  Oban worker job for each cleanup signal:

    - `:run_cleanup_needed` with action `:archive`      -> ArchiveRunWorker
    - `:run_cleanup_needed` with action `:reset_tasks`  -> ResetRunTasksWorker
    - `:session_cleanup_needed` with action `:disband`  -> DisbandTeamWorker
    - `:session_cleanup_needed` with action `:kill`     -> KillSessionWorker
  """

  use GenServer

  require Logger

  alias Ichor.Factory.Workers.ArchiveRunWorker
  alias Ichor.Factory.Workers.ResetRunTasksWorker
  alias Ichor.Infrastructure.Workers.DisbandTeamWorker
  alias Ichor.Infrastructure.Workers.KillSessionWorker
  alias Ichor.Signals.Message

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    Ichor.Signals.subscribe(:archon)
    {:ok, %{}}
  end

  @impl true
  def handle_info(
        %Message{name: :run_cleanup_needed, data: %{run_id: run_id, action: :archive}},
        state
      ) do
    insert_job(%{"run_id" => run_id}, ArchiveRunWorker)
    {:noreply, state}
  end

  @impl true
  def handle_info(
        %Message{name: :run_cleanup_needed, data: %{run_id: run_id, action: :reset_tasks}},
        state
      ) do
    insert_job(%{"run_id" => run_id}, ResetRunTasksWorker)
    {:noreply, state}
  end

  @impl true
  def handle_info(
        %Message{name: :session_cleanup_needed, data: %{session: session, action: :disband}},
        state
      ) do
    insert_job(%{"session" => session}, DisbandTeamWorker)
    {:noreply, state}
  end

  @impl true
  def handle_info(
        %Message{name: :session_cleanup_needed, data: %{session: session, action: :kill}},
        state
      ) do
    insert_job(%{"session" => session}, KillSessionWorker)
    {:noreply, state}
  end

  @impl true
  def handle_info(%Message{}, state), do: {:noreply, state}

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  defp insert_job(args, worker) do
    case args |> worker.new() |> Oban.insert() do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "[RunCleanupSubscriber] Failed to insert #{inspect(worker)} job #{inspect(args)}: #{inspect(reason)}"
        )
    end
  end
end
