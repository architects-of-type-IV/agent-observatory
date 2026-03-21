defmodule Ichor.Infrastructure.Workers.DisbandTeamWorker do
  @moduledoc """
  Disbands a team detected as needing cleanup by TeamWatchdog.

  Idempotent: FleetSupervisor.disband_team/1 is a no-op if the team is already gone.
  """

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 3,
    unique: [period: 60, keys: [:session]]

  require Logger

  alias Ichor.Infrastructure.FleetSupervisor

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"session" => session}}) do
    case FleetSupervisor.disband_team(session) do
      :ok ->
        :ok

      {:error, :not_found} ->
        # Team already gone -- idempotent no-op
        :ok

      {:error, reason} ->
        Logger.warning(
          "[DisbandTeamWorker] Failed to disband team #{session}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end
end
