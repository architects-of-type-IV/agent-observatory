defmodule Signals do
  @moduledoc """
  Stateful accumulators that correlate unrelated events into conclusions.

  No required dependencies.

  ## The idea

  > Every event in the system is a topic. Topics are the atoms. Signals are the
  > molecules.

  An event on its own says almost nothing. `agent.tool.invoked` is not a
  problem; the *same* tool invoked three times running is. `agent.session.started`
  is not a problem; started with nothing since is. No event carries that
  meaning, because the meaning is in the relationship between several of them.

  A **Signal** is where a few unrelated events become related. It picks a set of
  topics, keeps whatever state its own logic needs, and the moment that state
  means something, emits a signal event saying so.

      Event source → topic → Signal (accumulates) → signal.<name> → subscriber

  ## A signal is not a topic

  You cannot subscribe to a signal. A signal listens to topics and emits to one.
  It sits in the middle: it consumes topics, it emits topics, it is neither.

  That single rule is what makes meta-signals fall out for free. A signal
  declaring `topics: ["signal.*"]` consumes other signals' conclusions as its
  own input — no special mechanism, because an emission is an ordinary event.

  ## Setup

      children = [
        Signals.Store.ETS,
        Signals.Sink.Local,
        Signals.Registry,
        Signals.Supervisor
      ]

      config :signals,
        signals: [MyApp.Signals.LoopDetected, MyApp.Signals.Watchdog],
        store: Signals.Store.ETS,
        sink: Signals.Sink.Local

  Or start the lot with `Signals.Supervisor`, which includes the defaults.

  ## Use

      Signals.emit("agent.tool.invoked", subject: "agent-1", data: %{tool: "Read"})

      Signals.subscribe(["signal.*"])
      receive do
        {:signal, event} -> IO.inspect({event.type, event.data})
      end

  ## Writing one

  See `Signals.Signal`. Most signals are three or four callbacks — the topics
  they watch, what they remember, and when it means something.
  """

  alias Signals.Config
  alias Signals.Event
  alias Signals.Router

  @doc """
  Publish an event into the pipeline.

  Returns the signals it reached, so a caller can tell whether anything was
  listening at all.
  """
  @spec emit(String.t(), keyword()) :: [module()]
  def emit(type, opts \\ []) when is_binary(type) do
    type |> Event.new(opts) |> emit_event()
  end

  @doc "Publish an already-built event."
  @spec emit_event(Event.t()) :: [module()]
  defdelegate emit_event(event), to: Router, as: :dispatch

  @doc "Publish a batch, preserving per-subject order."
  @spec emit_many([Event.t()]) :: :ok
  defdelegate emit_many(events), to: Router, as: :dispatch_many

  @doc """
  Receive `{:signal, event}` for emissions matching `patterns`.

  Delegates to the configured sink, which must support it — the bundled
  `Signals.Sink.Local` does.
  """
  @spec subscribe([String.t()]) :: :ok
  def subscribe(patterns \\ ["*"]) do
    sink = Config.sink()

    if function_exported?(sink, :subscribe, 1) do
      sink.subscribe(patterns)
    else
      {:error, {:not_supported, sink}}
    end
  end

  @doc "The registered signal modules."
  @spec registered() :: [module()]
  defdelegate registered, to: Config, as: :signals

  @doc """
  The subscription graph — which signal watches what, and which are meta.

  The cross-influence map is this, rendered.
  """
  @spec subscriptions() :: [map()]
  defdelegate subscriptions, to: Router

  @doc "Every running accumulator, as `{signal, key, pid}`."
  @spec accumulators() :: [{module(), term(), pid()}]
  defdelegate accumulators, to: Signals.Registry, as: :list

  @doc """
  The accumulated state of one signal for one key, or `nil` if not running.

  For inspection — what has this signal seen so far, and how close is it?
  """
  @spec peek(module(), String.t() | nil) :: term() | nil
  def peek(signal, key \\ nil) do
    case Signals.Registry.whereis(signal, key) do
      nil -> nil
      pid -> Signals.Accumulator.peek(pid)
    end
  end
end
