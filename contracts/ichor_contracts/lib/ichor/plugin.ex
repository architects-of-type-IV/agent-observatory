defmodule Ichor.Plugin do
  @moduledoc """
  Behaviour that all MES-built plugins must implement.

  The contract is simple: implement `info/0` and the system discovers you.

  `info/0` returns a uniform manifest that the runtime uses to:
    1. Auto-subscribe the plugin to its unique PubSub topic
    2. Register its emitted signals in the catalog
    3. Display it in the dashboard
    4. Route control signals to it

  The PubSub topic (`info().topic`) is the plugin's address. Any module
  can send it signals via `Ichor.Signals.emit/3` with the topic as scope.
  The plugin receives them in `handle_signal/1`.

  ## Example

      defmodule Ichor.Plugins.WebhookNotifier do
        @behaviour Ichor.Plugin

        @impl true
        def info do
          %Ichor.Plugin.Info{
            name: "WebhookNotifier",
            module: __MODULE__,
            description: "Posts JSON to a configured URL when matching signals fire",
            topic: "plugin:webhook_notifier",
            version: "0.1.0",
            signals_emitted: [:webhook_sent, :webhook_failed],
            signals_subscribed: [:fleet, :mes],
            features: [
              "Configurable webhook URL and signal filter",
              "JSON payload with signal name, data, and timestamp",
              "Retry with exponential backoff on failure"
            ],
            use_cases: [
              "POST to local endpoint when a MES run finishes",
              "Notify self-hosted monitor when an agent crashes",
              "Send fleet events to an external logging service"
            ]
          }
        end

        @impl true
        def start, do: # start GenServer, subscribe to topic
        @impl true
        def handle_signal(message), do: # POST JSON to webhook URL
        @impl true
        def stop, do: # cleanup
      end
  """

  alias Ichor.Signals.Message

  @type info :: %Ichor.Plugin.Info{}

  @doc "Return the plugin's self-describing manifest. Must be a pure function (no side effects)."
  @callback info() :: info()

  @doc "Start the plugin. Subscribe to your topic here. Called after hot-loading."
  @callback start() :: :ok | {:error, term()}

  @doc "Handle an incoming signal routed to your topic."
  @callback handle_signal(Message.t()) :: :ok

  @doc "Graceful shutdown. Unsubscribe and clean up state."
  @callback stop() :: :ok
end
