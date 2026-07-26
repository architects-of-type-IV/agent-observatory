defmodule MemoryStore.Notifier do
  @moduledoc """
  Behaviour for reacting to memory mutations.

  In the original system these calls were events on a signal bus. Here the
  store depends only on this behaviour, so a host application can bridge them to
  whatever it already uses — PubSub, telemetry, a GenStage producer — without
  the store knowing about any of it.

  Notifications are observational: they fire after the mutation has already been
  applied to ETS, and the store neither waits for nor checks the result. Do not
  route work that must not be lost through here.

  Configure with:

      config :memory_store, notifier: MyApp.MemoryNotifier

  ## Events

  | Event | Fired when |
  |---|---|
  | `:agent_created` | `MemoryStore.create_agent/3` succeeds |
  | `:archival_insert` | `MemoryStore.archival_memory_insert/3` succeeds |
  """

  @typedoc "What happened."
  @type event :: :agent_created | :archival_insert

  @doc """
  Handle a memory mutation.

  Called from inside the `MemoryStore` process, so a slow implementation blocks
  the store. Hand off to another process if the work is not trivial. The return
  value is ignored; raising will crash the store.
  """
  @callback notify(event :: event(), agent_name :: String.t(), payload :: map()) :: any()
end

defmodule MemoryStore.Notifier.Noop do
  @moduledoc """
  Default notifier. Discards everything.

  Lets the store run standalone with no host wiring at all.
  """

  @behaviour MemoryStore.Notifier

  @impl true
  def notify(_event, _agent_name, _payload), do: :ok
end

defmodule MemoryStore.Notifier.ProcessMessage do
  @moduledoc """
  Notifier that sends `{:memory_store, event, agent_name, payload}` to a process.

  Useful in tests, and enough on its own for a single-consumer application.
  Configure the destination as a pid or a registered name:

      config :memory_store,
        notifier: MemoryStore.Notifier.ProcessMessage,
        notifier_target: MyApp.MemoryListener

  With no `:notifier_target` set, nothing is sent.
  """

  @behaviour MemoryStore.Notifier

  @impl true
  def notify(event, agent_name, payload) do
    case Application.get_env(:memory_store, :notifier_target) do
      nil -> :ok
      target -> send(target, {:memory_store, event, agent_name, payload})
    end

    :ok
  end
end
