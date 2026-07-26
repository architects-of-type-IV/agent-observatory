defmodule Signals.Sink.Local do
  @moduledoc """
  Default `Signals.Sink`: routes emissions back in, and forwards them to subscribers.

  Both halves matter. Re-routing is what lets a meta-signal treat another
  signal's conclusion as its own input; forwarding is what lets the world hear
  it. A sink that does only the second silently disables every meta-signal.

  Subscribers are processes registered with `subscribe/1`, which receive
  `{:signal, %Signals.Event{}}`. Enough on its own for a single node; swap in a
  PubSub-backed sink to reach further.
  """

  use GenServer

  @behaviour Signals.Sink

  alias Signals.Event

  @doc "Start the sink."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Receive `{:signal, event}` for emissions matching `patterns`.

  Patterns are `Signals.Topic` patterns over the emission type, so
  `["signal.*"]` is everything and `["signal.loop_detected"]` is one.
  """
  @spec subscribe([String.t()]) :: :ok
  def subscribe(patterns \\ ["*"]), do: GenServer.call(__MODULE__, {:subscribe, self(), patterns})

  @doc "Stop receiving emissions."
  @spec unsubscribe() :: :ok
  def unsubscribe, do: GenServer.call(__MODULE__, {:unsubscribe, self()})

  @impl Signals.Sink
  def publish(%Event{} = event) do
    # Route first: a meta-signal should see the conclusion before, or at worst
    # alongside, the outside world does.
    Signals.Router.dispatch(event)
    GenServer.cast(__MODULE__, {:publish, event})
  end

  @impl GenServer
  def init(_opts) do
    Process.flag(:trap_exit, true)
    {:ok, %{subscribers: %{}}}
  end

  @impl GenServer
  def handle_call({:subscribe, pid, patterns}, _from, state) do
    Process.monitor(pid)
    {:reply, :ok, put_in(state.subscribers[pid], patterns)}
  end

  def handle_call({:unsubscribe, pid}, _from, state) do
    {:reply, :ok, %{state | subscribers: Map.delete(state.subscribers, pid)}}
  end

  @impl GenServer
  def handle_cast({:publish, event}, state) do
    for {pid, patterns} <- state.subscribers,
        Signals.Topic.matches_any?(event.type, patterns) do
      send(pid, {:signal, event})
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | subscribers: Map.delete(state.subscribers, pid)}}
  end

  def handle_info(_message, state), do: {:noreply, state}
end

defmodule Signals.Sink.Collector do
  @moduledoc """
  `Signals.Sink` that records emissions without re-routing them.

  For asserting on what a signal concluded in isolation. Because it does not
  re-route, meta-signals see nothing — which is exactly what you want when
  testing one signal, and exactly wrong in production.
  """

  @behaviour Signals.Sink

  alias Signals.Event

  @table :signals_collector

  @doc "Start collecting, clearing anything from a previous test."
  @spec setup() :: :ok
  def setup do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :duplicate_bag])
    end

    :ets.delete_all_objects(@table)
    :ok
  end

  @impl true
  def publish(%Event{} = event) do
    :ets.insert(@table, {:emission, System.unique_integer([:monotonic]), event})
    :ok
  end

  @doc "Every emission so far, oldest first."
  @spec emissions() :: [Event.t()]
  def emissions do
    @table
    |> :ets.lookup(:emission)
    |> Enum.sort_by(fn {_, seq, _} -> seq end)
    |> Enum.map(fn {_, _, event} -> event end)
  end

  @doc "Emissions of one signal, by name."
  @spec emissions_of(String.t()) :: [Event.t()]
  def emissions_of(name) do
    Enum.filter(emissions(), &(Event.signal_name(&1) == name))
  end
end
