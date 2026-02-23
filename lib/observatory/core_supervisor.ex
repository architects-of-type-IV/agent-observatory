defmodule Observatory.CoreSupervisor do
  @moduledoc """
  Supervises core infrastructure services: mailbox, command queue, team watcher,
  notes, event janitor, and memory store. These are independent services that
  don't depend on each other, so one_for_one is appropriate.
  """
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {Observatory.Mailbox, []},
      {Observatory.CommandQueue, []},
      {Observatory.TeamWatcher, []},
      {Observatory.Notes, []},
      {Observatory.EventJanitor, []},
      {Observatory.MemoryStore, []},
      {Observatory.EventBuffer, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
