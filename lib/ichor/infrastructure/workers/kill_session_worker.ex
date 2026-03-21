defmodule Ichor.Infrastructure.Workers.KillSessionWorker do
  @moduledoc """
  Kills a tmux session detected as needing cleanup by TeamWatchdog.

  Idempotent: killing a dead tmux session is a no-op.
  """

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 3,
    unique: [period: 60, keys: [:session]]

  alias Ichor.Infrastructure.Cleanup

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"session" => session}}) do
    Cleanup.kill_session(session)
  end
end
