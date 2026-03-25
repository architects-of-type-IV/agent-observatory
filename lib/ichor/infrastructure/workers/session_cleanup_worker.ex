defmodule Ichor.Infrastructure.Workers.SessionCleanupWorker do
  @moduledoc """
  Handles session cleanup actions: killing tmux sessions and disbanding fleet teams.

  Accepts an `action` argument to dispatch to the appropriate cleanup operation:
    - `"kill"` -- kills the tmux session via `Cleanup.kill_session/1`
    - `"disband"` -- disbands the fleet team via `FleetSupervisor.disband_team/1`

  Idempotent: killing a dead session or disbanding a gone team are no-ops.
  """

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 3,
    unique: [period: 60, keys: [:session, :action]]

  alias Ichor.Infrastructure.Cleanup
  alias Ichor.Fleet.Supervisor, as: FleetSupervisor

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"session" => session, "action" => "kill"}}) do
    Cleanup.kill_session(session)
  end

  def perform(%Oban.Job{args: %{"session" => session, "action" => "disband"}}) do
    case FleetSupervisor.disband_team(session) do
      :ok -> :ok
      {:error, :not_found} -> :ok
    end
  end
end
