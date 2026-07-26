defmodule HostRegistry.Notifier do
  @moduledoc """
  Behaviour for reacting to changes in the set of known hosts.

  In the original system this was an event on a signal bus. Here the registry
  depends only on this behaviour, so a host application can bridge it to PubSub,
  telemetry, or anything else without the registry knowing.

  Configure with:

      config :host_registry, notifier: MyApp.HostNotifier

  ## Timing

  `hosts_changed/1` is called from inside the registry process, after the change
  has been applied — so a slow implementation blocks node up/down handling, and
  raising crashes the registry. Hand off to another process if the work is not
  trivial.
  """

  @doc """
  Handle a change to the host set.

  Called on registration, removal, and node up/down. Receives the full host list
  as it now stands, so a consumer can render it without calling back in. The
  return value is ignored.
  """
  @callback hosts_changed(hosts :: [map()]) :: any()
end

defmodule HostRegistry.Notifier.Noop do
  @moduledoc "Default notifier. Discards everything, so the registry runs unwired."

  @behaviour HostRegistry.Notifier

  @impl true
  def hosts_changed(_hosts), do: :ok
end

defmodule HostRegistry.Notifier.ProcessMessage do
  @moduledoc """
  Notifier that sends `{:host_registry, :hosts_changed, hosts}` to a process.

  Configure the destination as a pid or a registered name:

      config :host_registry,
        notifier: HostRegistry.Notifier.ProcessMessage,
        notifier_target: MyApp.FleetView

  With no `:notifier_target` set, nothing is sent.
  """

  @behaviour HostRegistry.Notifier

  @impl true
  def hosts_changed(hosts) do
    case Application.get_env(:host_registry, :notifier_target) do
      nil -> :ok
      target -> send(target, {:host_registry, :hosts_changed, hosts})
    end

    :ok
  end
end
