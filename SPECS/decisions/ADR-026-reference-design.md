# Ash + GenStage + Signals Architecture
A complete example of an Ash-based event pipeline where Ash Resources emit domain events, a GenStage ingress receives them, a router forwards them to keyed Signal processes, and each Signal decides when to emit a downstream signal.

---

## Goal

This example models this flow:

```text
Ash Action
  -> Domain Event
    -> Event Bus
      -> GenStage Ingress
        -> Signal Router
          -> Signal Process per {signal_name, key}
            -> Accumulate events
            -> When ready: emit Signal
              -> Signal Handler (Reactor / Oban / module / LLM)
```

---

## Compact mental model

- **Event** = something happened
- **Signal** = enough happened
- **Handler** = now act

---

## `lib/demo/events/event.ex`

The event envelope. One shape everywhere.

```elixir
defmodule Demo.Events.Event do
  @enforce_keys [:id, :topic, :key, :occurred_at, :data]
  defstruct [
    :id,
    :topic,
    :key,
    :occurred_at,
    :causation_id,
    :correlation_id,
    :data,
    :metadata
  ]

  def new(topic, key, data, metadata \\ %{}) do
    %__MODULE__{
      id: Ash.UUID.generate(),
      topic: topic,
      key: key,
      occurred_at: DateTime.utc_now(),
      causation_id: nil,
      correlation_id: nil,
      data: data,
      metadata: metadata
    }
  end
end
```

---

## `lib/demo/signals/signal.ex`

The signal envelope. Emitted when a signal process decides "enough happened."

```elixir
defmodule Demo.Signals.Signal do
  @enforce_keys [:name, :key, :events, :emitted_at]
  defstruct [:name, :key, :events, :metadata, :emitted_at]

  def new(name, key, events, metadata \\ %{}) do
    %__MODULE__{
      name: name,
      key: key,
      events: events,
      metadata: metadata,
      emitted_at: DateTime.utc_now()
    }
  end
end
```

---

## `lib/demo/signals/behaviour.ex`

Every signal module implements this behaviour.

```elixir
defmodule Demo.Signals.Behaviour do
  alias Demo.Events.Event
  alias Demo.Signals.Signal

  @callback topics() :: [String.t()]
  @callback init_state(key :: term()) :: map()
  @callback handle_event(state :: map(), event :: Event.t()) :: map()
  @callback ready?(state :: map(), trigger :: :event | :timer) :: boolean()
  @callback build_signal(state :: map()) :: Signal.t() | nil
  @callback reset(state :: map()) :: map()
end
```

---

## `lib/demo/events.ex`

The event bus. Accepts events and pushes them into GenStage.

```elixir
defmodule Demo.Events do
  alias Demo.Events.Event

  def emit(%Event{} = event) do
    Demo.Events.Ingress.push(event)
    :ok
  end
end
```

---

## `lib/demo/events/ingress.ex`

GenStage producer. Bridges the event bus into demand-driven flow.

```elixir
defmodule Demo.Events.Ingress do
  use GenStage

  def start_link(_opts) do
    GenStage.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def push(event) do
    GenServer.cast(__MODULE__, {:push, event})
  end

  @impl true
  def init(:ok) do
    {:producer, {:queue.new(), 0}}
  end

  @impl true
  def handle_cast({:push, event}, {queue, demand}) do
    queue = :queue.in(event, queue)
    dispatch_events(queue, demand, [])
  end

  @impl true
  def handle_demand(incoming_demand, {queue, demand}) do
    dispatch_events(queue, demand + incoming_demand, [])
  end

  defp dispatch_events(queue, demand, events) when demand > 0 do
    case :queue.out(queue) do
      {{:value, event}, queue} ->
        dispatch_events(queue, demand - 1, [event | events])

      {:empty, queue} ->
        {:noreply, Enum.reverse(events), {queue, demand}}
    end
  end

  defp dispatch_events(queue, 0, events) do
    {:noreply, Enum.reverse(events), {queue, 0}}
  end
end
```

---

## `lib/demo/signals/router.ex`

GenStage consumer that routes events to the correct signal process.

```elixir
defmodule Demo.SignalRouter do
  use GenStage

  @signal_modules [
    Demo.Signals.ConversationSummary
  ]

  def start_link(_opts) do
    GenStage.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    {:consumer, :ok, subscribe_to: [{Demo.Events.Ingress, max_demand: 50}]}
  end

  @impl true
  def handle_events(events, _from, state) do
    Enum.each(events, fn event ->
      Enum.each(@signal_modules, fn mod ->
        if event.topic in mod.topics() do
          Demo.SignalProcess.route(mod, event)
        end
      end)
    end)

    {:noreply, [], state}
  end
end
```

---

## `lib/demo/signals/signal_process.ex`

One process per `{signal_module, key}`. Accumulates events and flushes when ready.

```elixir
defmodule Demo.SignalProcess do
  use GenServer

  @flush_interval :timer.seconds(30)

  def route(signal_module, event) do
    name = via(signal_module, event.key)

    case GenServer.whereis(name) do
      nil ->
        DynamicSupervisor.start_child(
          Demo.SignalSupervisor,
          {__MODULE__, {signal_module, event.key}}
        )

        GenServer.cast(name, {:event, event})

      _pid ->
        GenServer.cast(name, {:event, event})
    end
  end

  def start_link({signal_module, key}) do
    GenServer.start_link(__MODULE__, {signal_module, key}, name: via(signal_module, key))
  end

  defp via(signal_module, key) do
    {:via, Registry, {Demo.SignalRegistry, {signal_module, key}}}
  end

  @impl true
  def init({signal_module, key}) do
    state = %{
      module: signal_module,
      key: key,
      inner: signal_module.init_state(key),
      timer: schedule_flush()
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:event, event}, state) do
    inner = state.module.handle_event(state.inner, event)
    state = %{state | inner: inner}

    if state.module.ready?(inner, :event) do
      flush_and_reset(state)
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:flush, state) do
    if state.module.ready?(state.inner, :timer) do
      flush_and_reset(state)
    else
      {:noreply, %{state | timer: schedule_flush()}}
    end
  end

  defp flush_and_reset(state) do
    case state.module.build_signal(state.inner) do
      nil ->
        {:noreply, %{state | inner: state.module.reset(state.inner), timer: schedule_flush()}}

      signal ->
        Demo.SignalHandler.handle(signal)
        {:noreply, %{state | inner: state.module.reset(state.inner), timer: schedule_flush()}}
    end
  end

  defp schedule_flush do
    Process.send_after(self(), :flush, @flush_interval)
  end
end
```

---

## `lib/demo/signals/conversation_summary.ex`

Example signal module. Accumulates chat messages, flushes when 5 messages or conversation closed.

```elixir
defmodule Demo.Signals.ConversationSummary do
  @behaviour Demo.Signals.Behaviour

  alias Demo.Events.Event
  alias Demo.Signals.Signal

  @flush_size 5

  def topics do
    ["chat.message.created", "chat.conversation.closed"]
  end

  def init_state(key) do
    %{key: key, events: [], counts: %{}, closed?: false}
  end

  def handle_event(state, %Event{} = event) do
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

  defp append_event(state, event) do
    %{state | events: [event | state.events]}
  end

  defp increment_topic_count(state, topic) do
    update_in(state.counts, fn counts ->
      Map.update(counts, topic, 1, &(&1 + 1))
    end)
  end

  defp maybe_mark_closed(state, %Event{topic: "chat.conversation.closed"}) do
    %{state | closed?: true}
  end

  defp maybe_mark_closed(state, _event), do: state

  defp enough_events?(state) do
    length(state.events) >= @flush_size
  end
end
```

---

## `lib/demo/signal_handler.ex`

This is the downstream reaction to a signal.

In a real app this could:
- enqueue Oban
- call Ash Reactor
- trigger summarization
- write a projection
- continue another workflow

```elixir
defmodule Demo.SignalHandler do
  alias Demo.Signals.Signal

  def handle(%Signal{name: "conversation.summary.ready"} = signal) do
    messages = extract_messages(signal.events)

    IO.puts("""
    SIGNAL EMITTED
    name: #{signal.name}
    key: #{signal.key}
    message_count: #{length(messages)}
    preview: #{preview(messages)}
    """)

    :ok
  end

  def handle(%Signal{} = signal) do
    IO.inspect(signal, label: "Unhandled signal")
    :ok
  end

  defp extract_messages(events) do
    events
    |> Enum.filter(fn event -> Map.has_key?(event.data, :content) end)
    |> Enum.map(fn event ->
      %{
        role: Map.get(event.data, :role),
        content: Map.get(event.data, :content)
      }
    end)
  end

  defp preview([]), do: ""

  defp preview(messages) do
    messages
    |> Enum.take(2)
    |> Enum.map_join(" | ", fn %{role: role, content: content} ->
      "#{role}: #{String.slice(content, 0, 40)}"
    end)
  end
end
```

---

## `lib/demo/chat/message.ex`

This Ash resource emits an event after `create`.

```elixir
defmodule Demo.Chat.Message do
  use Ash.Resource,
    domain: Demo.Chat,
    data_layer: Ash.DataLayer.Ets

  ets do
    private? false
    table :messages
  end

  attributes do
    uuid_primary_key :id

    attribute :conversation_id, :uuid do
      allow_nil? false
    end

    attribute :role, :atom do
      allow_nil? false
      constraints one_of: [:user, :assistant, :system]
    end

    attribute :content, :string do
      allow_nil? false
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:conversation_id, :role, :content]

      change after_action(fn _changeset, record, _context ->
               Demo.Events.emit(
                 Demo.Events.Event.new(
                   "chat.message.created",
                   record.conversation_id,
                   %{
                     message_id: record.id,
                     conversation_id: record.conversation_id,
                     role: record.role,
                     content: record.content
                   },
                   %{
                     resource: "Demo.Chat.Message",
                     action: "create"
                   }
                 )
               )

               {:ok, record}
             end)
    end
  end
end
```

---

## `lib/demo/chat/events.ex`

Optional explicit terminal event.

```elixir
defmodule Demo.Chat.Events do
  def conversation_closed(conversation_id) do
    Demo.Events.emit(
      Demo.Events.Event.new(
        "chat.conversation.closed",
        conversation_id,
        %{conversation_id: conversation_id},
        %{source: "manual"}
      )
    )
  end
end
```

---

## Example usage

```elixir
alias Demo.Chat
alias Demo.Chat.Message

conversation_id = Ash.UUID.generate()

Ash.create!(
  Message,
  %{
    conversation_id: conversation_id,
    role: :user,
    content: "I want a signal system that accumulates events."
  },
  domain: Chat
)

Ash.create!(
  Message,
  %{
    conversation_id: conversation_id,
    role: :assistant,
    content: "Then use Ash to emit events and let signals decide readiness."
  },
  domain: Chat
)

Ash.create!(
  Message,
  %{
    conversation_id: conversation_id,
    role: :user,
    content: "I want the signal to flush when enough context exists."
  },
  domain: Chat
)

Ash.create!(
  Message,
  %{
    conversation_id: conversation_id,
    role: :assistant,
    content: "Good. Keep the signal small and move real work to handlers."
  },
  domain: Chat
)

Ash.create!(
  Message,
  %{
    conversation_id: conversation_id,
    role: :user,
    content: "Show me the full design."
  },
  domain: Chat
)
```

The fifth message causes `Demo.Signals.ConversationSummary` to become ready and emit a signal.

You can also trigger a flush with an explicit closing event:

```elixir
Demo.Chat.Events.conversation_closed(conversation_id)
```

---

## Why this design is good

### 1. Ash stays in its lane
Ash validates commands and emits domain events.

### 2. Signals stay small
The signal process only:
- accumulates
- decides readiness
- emits a signal

It does not become a giant orchestration blob.

### 3. Handlers do the real work
The signal handler can call:
- Reactor
- Oban
- another Ash action
- external APIs
- LLM workflows

### 4. One event can feed multiple signal families
Just add more signal modules to `Demo.SignalRouter`.

For example:

```elixir
@signal_modules [
  Demo.Signals.ConversationSummary,
  Demo.Signals.EntityExtraction,
  Demo.Signals.FactExtraction
]
```

Then one event can route into several downstream decisions.

---

## Next step pattern

When you want to expand this, do it like this:

### Add another signal module
For example:

- `Demo.Signals.EntityExtraction`
- `Demo.Signals.TopicShift`
- `Demo.Signals.AgentHandoffReady`

Each one implements `Demo.Signals.Behaviour`.

### Keep routing declarative
Let the signal module itself decide whether it accepts an event.

### Keep handlers replaceable
The signal handler can later dispatch based on signal name to:
- Oban jobs
- Reactor workflows
- domain modules

---

## Practical notes

### PubSub is optional for core flow
PubSub is useful for:
- LiveView dashboards
- logs
- metrics
- observer tooling

But the core signal path is:

```text
Ash -> Events -> GenStage -> SignalRouter -> SignalProcess -> SignalHandler
```

### This is not durable event sourcing yet
This example is runtime accumulation.

If you later want durability, add:
- append-only event storage
- replay support
- idempotency
- signal checkpoints

But for the architecture you asked for, this is the correct runtime shape.

---

## Compact mental model

- **Event** = something happened
- **Signal** = enough happened
- **Handler** = now act

That naming stays clean as the system grows.
