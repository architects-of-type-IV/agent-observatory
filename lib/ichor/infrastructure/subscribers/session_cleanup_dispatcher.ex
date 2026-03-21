defmodule Ichor.Infrastructure.Subscribers.SessionCleanupDispatcher do
  @moduledoc """
  Infrastructure subscriber for session cleanup signals emitted by TeamWatchdog.

  Subscribes to the `:archon` signal category and reacts to
  `:session_cleanup_needed` signals by inserting the appropriate Infrastructure
  Oban worker jobs.  All Oban inserts are domain-local -- no cross-domain
  imports.
  """

  use GenServer

  require Logger

  alias Ichor.Infrastructure.Workers.DisbandTeamWorker
  alias Ichor.Infrastructure.Workers.KillSessionWorker
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

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp insert_job(args, worker, unique_opts) do
    case args |> worker.new(unique: unique_opts) |> Oban.insert() do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "[SessionCleanupDispatcher] Failed to insert #{inspect(worker)} job #{inspect(args)}: #{inspect(reason)}"
        )
    end
  end
end
