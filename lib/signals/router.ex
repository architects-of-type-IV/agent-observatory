defmodule Signals.Router do
  @moduledoc """
  Sends each event to every signal that declared an interest in it.

  The router owns no logic of its own. It reads `c:Signals.Signal.topics/0`,
  matches, and dispatches — which is why the topic list is declarative: it is
  the only thing standing between an event and a signal, and it can be inspected
  without running anything.

  ## Fan-out

  One event can reach many signals, and usually does. `agent.crashed` feeds a
  crash-rate signal, a fleet-health signal, and a watchdog at once, each drawing
  a different conclusion. That is the point — the same fact means different
  things in different company.

  ## Partitioning

  Each signal decides its own accumulator key via
  `c:Signals.Signal.partition_key/1`, defaulting to the event's `subject`. So
  the same event can land in a per-agent accumulator for one signal and a
  fleet-wide one for another, which is what lets a crash-cascade signal count
  across agents while a loop detector reasons about one.

  Within a key, delivery preserves arrival order — a sequence-sensitive signal
  drawing conclusions from a shuffled history would be worse than one drawing
  none.
  """

  require Logger

  alias Signals.Config
  alias Signals.Event
  alias Signals.Registry
  alias Signals.Topic

  @doc """
  Route one event to every interested signal.

  Returns the modules it was delivered to, which is what makes routing testable
  without inspecting accumulator state.
  """
  @spec dispatch(Event.t()) :: [module()]
  def dispatch(%Event{} = event) do
    event
    |> interested()
    |> Enum.filter(&deliver(&1, event))
  end

  @doc """
  Route a batch, preserving per-subject order.

  Events for different subjects are independent; events for the same subject are
  delivered in the order given.
  """
  @spec dispatch_many([Event.t()]) :: :ok
  def dispatch_many(events) when is_list(events) do
    Enum.each(events, &dispatch/1)
  end

  @doc """
  The signals that would receive this event.

      iex> Signals.Router.interested(Signals.Event.new("nothing.matches.this"))
      []
  """
  @spec interested(Event.t()) :: [module()]
  def interested(%Event{type: type}) do
    Enum.filter(Config.signals(), fn signal ->
      Topic.matches_any?(type, signal.topics())
    end)
  end

  @doc """
  The subscription graph: which signal watches which patterns.

  Rendering the cross-influence map means asking this, not reading code.

      iex> is_list(Signals.Router.subscriptions())
      true
  """
  @spec subscriptions() :: [
          %{signal: module(), name: String.t(), topics: [String.t()], meta?: boolean()}
        ]
  def subscriptions do
    Enum.map(Config.signals(), fn signal ->
      topics = signal.topics()

      %{signal: signal, name: signal.name(), topics: topics, meta?: Topic.meta?(topics)}
    end)
  end

  defp deliver(signal, event) do
    case Registry.ensure(signal, signal.partition_key(event)) do
      {:ok, pid} ->
        Signals.Accumulator.push(pid, event)
        true

      {:error, reason} ->
        Logger.error(
          "[Signals] no accumulator for #{inspect(signal)} key=#{inspect(event.subject)}: " <>
            inspect(reason)
        )

        false
    end
  end
end
