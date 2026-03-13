defmodule Ichor.Mes.Subsystem do
  @moduledoc """
  Behaviour that all MES-built subsystems must implement.

  The contract is simple: implement `info/0` and the system discovers you.

  `info/0` returns a uniform manifest that the runtime uses to:
    1. Auto-subscribe the subsystem to its unique PubSub topic
    2. Register its emitted signals in the catalog
    3. Display it in the dashboard
    4. Route control signals to it

  The PubSub topic (`info().topic`) is the subsystem's address. Any module
  can send it signals via `Ichor.Signals.emit/3` with the topic as scope.
  The subsystem receives them in `handle_signal/1`.

  ## Example

      defmodule Ichor.Subsystems.Correlator do
        @behaviour Ichor.Mes.Subsystem

        @impl true
        def info do
          %Ichor.Mes.Subsystem.Info{
            name: "Correlator",
            module: __MODULE__,
            description: "Real-time causal signal correlation engine",
            topic: "subsystem:correlator",
            version: "0.1.0",
            signals_emitted: [:correlator_pattern_found, :correlator_pattern_lost],
            signals_subscribed: [:all],
            features: [
              "Sliding-window temporal co-occurrence matrix",
              "Granger-causality scoring between signal pairs",
              "Synthetic meta-signal emission on pattern detection"
            ],
            use_cases: [
              "Detect that agent_crashed follows entropy_spike within 200ms",
              "Surface hidden dependencies between fleet events",
              "Alert when a known correlation disappears"
            ]
          }
        end

        @impl true
        def start, do: # start GenServer, subscribe to topic
        @impl true
        def handle_signal(message), do: # process incoming signal
        @impl true
        def stop, do: # cleanup
      end
  """

  alias Ichor.Signals.Message

  @type info :: %Ichor.Mes.Subsystem.Info{}

  @doc "Return the subsystem's self-describing manifest. Must be a pure function (no side effects)."
  @callback info() :: info()

  @doc "Start the subsystem. Subscribe to your topic here. Called after hot-loading."
  @callback start() :: :ok | {:error, term()}

  @doc "Handle an incoming signal routed to your topic."
  @callback handle_signal(Message.t()) :: :ok

  @doc "Graceful shutdown. Unsubscribe and clean up state."
  @callback stop() :: :ok
end
