defmodule Signals.Accumulator do
  @moduledoc """
  One signal's reasoning about one partition key, as a process.

  There is an accumulator per `{signal, subject}` — one per agent for a
  per-agent signal, one globally for a fleet-wide one. Each holds its own
  partial conclusion and asks its signal, after every event and on every timer
  tick, whether that partial conclusion has become a real one.

  ## Durability

  State is written after each folded event. A half-accumulated signal is not
  recoverable from the event log alone unless you replay everything, so the
  partial conclusion is persisted rather than rebuilt.

  ## Idempotency

  A redelivered event is recognised by its identity — `{source, id}`, which
  CloudEvents already requires to be unique — via `Signals.Dedup`. Not by log
  position: events from a browser or a clock carry no position, and with more
  than one producer positions arrive out of order, where a high-water mark
  silently discards legitimate late arrivals.

  Position is still tracked and persisted, for the different question of where
  a replay should resume.

  Double-folding matters more than it sounds. It is not a crash — it is a
  crash-rate signal that fires at two crashes instead of five, quietly, and
  reads as working.

  ## Emission

  When `ready?/2` says so, the signal builds a payload and the accumulator wraps
  it in a `signal.<name>` event and hands it to the sink. Then it resets. The
  emission carries the causal depth of whatever triggered it, so
  meta-signals feeding each other terminate rather than spin.
  """

  use GenServer

  require Logger

  alias Signals.Config
  alias Signals.Event

  @typedoc false
  @type state :: %{
          signal: module(),
          key: String.t() | nil,
          data: term(),
          position: integer() | nil,
          seen: Signals.Dedup.t(),
          timer: reference() | nil
        }

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    signal = Keyword.fetch!(opts, :signal)
    key = Keyword.get(opts, :key)

    GenServer.start_link(__MODULE__, %{signal: signal, key: key},
      name: Signals.Registry.via(signal, key)
    )
  end

  @doc false
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: {__MODULE__, Keyword.fetch!(opts, :signal), Keyword.get(opts, :key)},
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient
    }
  end

  @doc "Fold an event into this accumulator."
  @spec push(pid(), Event.t()) :: :ok
  def push(pid, %Event{} = event), do: GenServer.cast(pid, {:event, event})

  @doc "The current accumulated state. For inspection and tests."
  @spec peek(pid()) :: term()
  def peek(pid), do: GenServer.call(pid, :peek)

  @doc "Ask now whether the accumulation has become a conclusion, as a `:timer` trigger."
  @spec tick(pid()) :: :ok
  def tick(pid), do: GenServer.cast(pid, :tick)

  @impl true
  def init(%{signal: signal, key: key}) do
    Process.flag(:trap_exit, true)
    {data, position, seen} = restore(signal, key)

    {:ok,
     %{
       signal: signal,
       key: key,
       data: data,
       position: position,
       seen: seen,
       timer: schedule(signal.interval())
     }}
  end

  @impl true
  def handle_cast({:event, %Event{} = event}, state) do
    if Signals.Dedup.seen?(state.seen, event) do
      {:noreply, state}
    else
      data = state.signal.handle_event(event, state.data)

      %{
        state
        | data: data,
          position: max_position(state.position, Event.position(event)),
          seen: Signals.Dedup.put(state.seen, event)
      }
      |> persist()
      |> evaluate(:event, depth_of(event))
      |> then(&{:noreply, &1})
    end
  end

  def handle_cast(:tick, state), do: {:noreply, evaluate(state, :timer, 0)}

  @impl true
  def handle_call(:peek, _from, state), do: {:reply, state.data, state}

  @impl true
  def handle_info(:tick, state) do
    state
    |> evaluate(:timer, 0)
    |> Map.put(:timer, schedule(state.signal.interval()))
    |> then(&{:noreply, &1})
  end

  def handle_info(message, state) do
    {:noreply, %{state | data: state.signal.handle_info(message, state.data)}}
  end

  @impl true
  def terminate(_reason, state) do
    persist(state)
    :ok
  end

  # The high-water mark for resuming a replay. Kept as a maximum rather than
  # last-write-wins, so an out-of-order arrival cannot rewind the checkpoint.
  defp max_position(current, nil), do: current
  defp max_position(nil, incoming), do: incoming
  defp max_position(current, incoming), do: max(current, incoming)

  defp evaluate(state, trigger, depth) do
    if state.signal.ready?(state.data, trigger) do
      emit(state, depth)
    else
      state
    end
  end

  defp emit(state, depth) do
    case state.signal.build_emission(state.data) do
      nil ->
        state

      payload ->
        state
        |> build_event(payload, depth)
        |> publish(depth)

        %{state | data: state.signal.reset(state.data)} |> persist()
    end
  end

  defp build_event(state, payload, depth) do
    name = state.signal.name()

    Event.new(Signals.Topic.emission_type(name),
      source: "signal/" <> name,
      subject: state.key,
      data: payload,
      extensions: %{depth: depth + 1}
    )
  end

  # A meta-signal consuming its own family of emissions could otherwise emit
  # forever, and a loop of signals looks identical to healthy throughput.
  defp publish(event, depth) do
    if depth + 1 > Config.max_emission_depth() do
      Logger.warning(
        "[Signals] dropping #{event.type}: emission depth #{depth + 1} exceeds " <>
          "max_emission_depth #{Config.max_emission_depth()}"
      )
    else
      Config.sink().publish(event)
    end
  end

  defp depth_of(%Event{extensions: ext}), do: Map.get(ext, :depth, 0)

  defp persist(state) do
    case Config.store().put(ref(state), {state.data, state.seen}, state.position) do
      :ok ->
        state

      {:error, reason} ->
        Logger.warning("[Signals] failed to persist #{inspect(ref(state))}: #{inspect(reason)}")
        state
    end
  end

  defp restore(signal, key) do
    case Config.store().fetch({signal.name(), key}) do
      {:ok, %{state: {data, %Signals.Dedup{} = seen}, position: position}} ->
        {data, position, seen}

      # Written before dedup state was persisted, or by a store that only kept
      # the signal's own state. Resume the accumulation, start dedup fresh.
      {:ok, %{state: data, position: position}} when not is_nil(data) ->
        {data, position, Signals.Dedup.new(Config.dedup_window())}

      _ ->
        {signal.init(key), nil, Signals.Dedup.new(Config.dedup_window())}
    end
  end

  defp ref(state), do: {state.signal.name(), state.key}

  defp schedule(nil), do: nil
  defp schedule(interval), do: Process.send_after(self(), :tick, interval)
end
