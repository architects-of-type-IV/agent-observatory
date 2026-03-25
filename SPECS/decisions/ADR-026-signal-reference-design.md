# ADR-026 Reference Design: Ash + GenStage + Signals Architecture

A complete example of an Ash-based event pipeline where Ash Resources emit domain events,
a GenStage ingress receives them, a router forwards them to keyed Signal processes, and
each Signal decides when to emit a downstream signal.

---

## Goal

```text
Ash Action
  -> Domain Event
    -> Event Bus
      -> GenStage Ingress
        -> Signal Router
          -> Signal Process per {signal_name, key}
            -> accumulate events
            -> decide readiness
            -> emit signal
              -> Signal Handler
```

### Terms

- **Event**: something happened in the domain
- **Signal**: enough happened to justify action
- **Signal Handler**: the code that reacts to an emitted signal

---

## Key Design Rules

### 1. Ash stays in its lane
Ash validates commands and emits domain events.

### 2. Signals stay small
The signal process only: accumulates, decides readiness, emits a signal.
It does not become a giant orchestration blob.

### 3. Handlers do the real work
The signal handler can call: Reactor, Oban, another Ash action, external APIs, LLM workflows.

### 4. One event can feed multiple signal families
Just add more signal modules to the router.

### 5. PubSub is optional for core flow
PubSub is useful for: LiveView dashboards, logs, metrics, observer tooling.
Core path: Ash -> Events -> GenStage -> SignalRouter -> SignalProcess -> SignalHandler

### 6. Signal modules decide acceptance
`accepts?/1` on the module -- not a static routing table.

### 7. Handler is separate from signal
Signal = when to fire. Handler = what to do. Different concerns.

---

## Behaviour Contract

```elixir
defmodule Demo.Signals.Behaviour do
  alias Demo.Events.Event
  alias Demo.Signals.Signal

  @callback name() :: atom()
  @callback accepts?(Event.t() | map()) :: boolean()
  @callback init(key :: term()) :: map()
  @callback handle_event(Event.t() | map(), state :: map()) :: map()
  @callback ready?(state :: map(), reason :: :event | :timer) :: boolean()
  @callback build_signal(state :: map()) :: Signal.t() | nil
  @callback reset(state :: map()) :: map()
end
```

---

## Signal Module Example

```elixir
defmodule Demo.Signals.ConversationSummary do
  @behaviour Demo.Signals.Behaviour

  alias Demo.Events.Event
  alias Demo.Signals.Signal

  @accepted_topics [
    "chat.message.created",
    "chat.message.updated",
    "chat.conversation.closed"
  ]

  @flush_size 5

  def name, do: :conversation_summary

  def accepts?(%Event{topic: topic}), do: topic in @accepted_topics

  def init(key) do
    %{key: key, events: [], counts: %{}, closed?: false}
  end

  def handle_event(%Event{} = event, state) do
    state
    |> append_event(event)
    |> increment_topic_count(event.topic)
    |> maybe_mark_closed(event)
  end

  def ready?(state, :event) do
    enough_events?(state) or state.closed?
  end

  def ready?(state, :timer) do
    state.events != []
  end

  def build_signal(%{events: []}), do: nil

  def build_signal(state) do
    ordered_events = Enum.reverse(state.events)

    Signal.new(
      "conversation.summary.ready",
      state.key,
      ordered_events,
      %{
        event_count: length(ordered_events),
        topic_counts: state.counts,
        closed?: state.closed?
      }
    )
  end

  def reset(state) do
    %{state | events: [], counts: %{}, closed?: false}
  end

  defp append_event(state, event), do: %{state | events: [event | state.events]}

  defp increment_topic_count(state, topic) do
    update_in(state.counts, fn counts -> Map.update(counts, topic, 1, &(&1 + 1)) end)
  end

  defp maybe_mark_closed(state, %Event{topic: "chat.conversation.closed"}), do: %{state | closed?: true}
  defp maybe_mark_closed(state, _event), do: state

  defp enough_events?(state), do: length(state.events) >= @flush_size
end
```

---

## Signal Handler (separate module)

```elixir
defmodule Demo.SignalHandler do
  alias Demo.Signals.Signal

  def handle(%Signal{name: "conversation.summary.ready"} = signal) do
    # Enqueue Oban, call Reactor, trigger summarization, write projection
    :ok
  end

  def handle(%Signal{} = signal) do
    IO.inspect(signal, label: "Unhandled signal")
    :ok
  end
end
```

---

## Signal Process (generic, delegates to module)

```elixir
defmodule Demo.Signals.Process do
  use GenServer

  @flush_interval 10_000

  def start_link(opts) do
    signal_module = Keyword.fetch!(opts, :signal)
    key = Keyword.fetch!(opts, :key)
    GenServer.start_link(__MODULE__, %{signal_module: signal_module, key: key},
      name: via(signal_module, key))
  end

  def via(signal_module, key) do
    {:via, Registry, {Demo.SignalRegistry, {signal_module, key}}}
  end

  def init(%{signal_module: signal_module, key: key}) do
    state = %{signal_module: signal_module, key: key, data: signal_module.init(key), timer_ref: nil}
    {:ok, schedule_flush(state)}
  end

  def handle_cast({:event, event}, state) do
    state = state |> apply_event(event) |> maybe_emit(:event)
    {:noreply, state}
  end

  def handle_info(:flush, state) do
    state = state |> clear_timer() |> maybe_emit(:timer) |> schedule_flush()
    {:noreply, state}
  end

  defp apply_event(%{signal_module: m, data: d} = s, event), do: %{s | data: m.handle_event(event, d)}

  defp maybe_emit(%{signal_module: m, data: d} = s, reason) do
    if m.ready?(d, reason), do: emit_signal(s), else: s
  end

  defp emit_signal(%{signal_module: m, data: d} = s) do
    case m.build_signal(d) do
      nil -> s
      signal -> :ok = Demo.SignalHandler.handle(signal); %{s | data: m.reset(d)}
    end
  end

  defp schedule_flush(s), do: %{s | timer_ref: Process.send_after(self(), :flush, @flush_interval)}
  defp clear_timer(%{timer_ref: nil} = s), do: s
  defp clear_timer(%{timer_ref: ref} = s), do: (Process.cancel_timer(ref); %{s | timer_ref: nil})
end
```

---

## Signal Router (consumer, uses accepts?/1)

```elixir
defmodule Demo.SignalRouter do
  use GenStage

  @signal_modules [Demo.Signals.ConversationSummary]

  def start_link(_opts), do: GenStage.start_link(__MODULE__, :ok, name: __MODULE__)

  def init(:ok), do: {:consumer, :ok, subscribe_to: [Demo.EventStage]}

  def handle_events(events, _from, state) do
    Enum.each(events, &route/1)
    {:noreply, [], state}
  end

  defp route(event) do
    @signal_modules
    |> Enum.filter(& &1.accepts?(event))
    |> Enum.each(fn m ->
      {:ok, pid} = Demo.SignalManager.ensure_signal(m, event.key)
      GenServer.cast(pid, {:event, event})
    end)
  end
end
```

---

## Compact mental model

- **Event** = something happened
- **Signal** = enough happened
- **Handler** = now act
