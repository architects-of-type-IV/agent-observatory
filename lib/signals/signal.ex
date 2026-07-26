defmodule Signals.Signal do
  @moduledoc """
  The contract a signal implements: what to watch, what to remember, when it means something.

  A signal is where **unrelated events become related**. Nothing about
  `agent.tool.completed` and `time.tick` connects them; a loop detector connects
  them, by choosing to watch both and applying logic across the pair. The
  correlation is the signal's whole content.

  Three parts, and they are deliberately separate:

  | Part | Callback | Question |
  |---|---|---|
  | Selection | `c:topics/0` | Which unrelated events might mean something together? |
  | Accumulation | `c:handle_event/2` | What do I need to remember? |
  | Conclusion | `c:ready?/2`, `c:build_emission/1` | Has it become true, and what do I say? |

  ## A signal is not a topic

  You cannot subscribe to a signal. A signal *listens* to topics and *emits* to
  one — `signal.<name>` — and consumers subscribe to that. Signal sits in the
  middle: it consumes topics, it emits topics, it is neither.

  This is why meta-signals need no special support. A signal that declares
  `topics: ["signal.*"]` consumes other signals' conclusions as its own input,
  because an emission is an ordinary event.

  ## Triggers

  `c:ready?/2` is asked after every accumulated event (`:event`) and on a timer
  (`:timer`) when `c:interval/0` returns a period. Timers are how a signal
  concludes something from *absence* — silence, staleness, a lull — which no
  arriving event can tell it.

  ## State is opaque

  `c:init/1` returns whatever the signal wants. The runtime never inspects it;
  it only hands it back. Different signals need genuinely different internal
  logic, and constraining the shape would be constraining the reasoning.

  ## Example

      defmodule MyApp.Signals.LoopDetected do
        use Signals.Signal

        @impl true
        def name, do: "loop_detected"

        @impl true
        def topics, do: ["agent.tool.invoked"]

        @impl true
        def init(key), do: %{key: key, recent: []}

        @impl true
        def handle_event(event, state) do
          %{state | recent: Enum.take([event.data["tool"] | state.recent], 5)}
        end

        @impl true
        def ready?(%{recent: [t, t, t | _]}, _trigger), do: true
        def ready?(_state, _trigger), do: false

        @impl true
        def build_emission(%{key: key, recent: [tool | _]}) do
          %{agent_id: key, tool: tool, reason: "same tool three times running"}
        end

        @impl true
        def reset(state), do: %{state | recent: []}
      end
  """

  alias Signals.Event

  @typedoc "Whatever the signal keeps between events. Opaque to the runtime."
  @type state :: term()

  @typedoc "Why `ready?/2` is being asked."
  @type trigger :: :event | :timer

  @doc "Stable name. Emissions are published as `signal.<name>`."
  @callback name() :: String.t()

  @doc """
  Topic patterns this signal watches. See `Signals.Topic` for wildcards.

  The claim about which unrelated events belong together.
  """
  @callback topics() :: [String.t()]

  @doc """
  Milliseconds between `:timer` checks, or `nil` for event-driven only.

  Needed whenever a conclusion depends on something *not* happening.
  """
  @callback interval() :: pos_integer() | nil

  @doc """
  Which accumulator this event belongs to.

  Defaults to the event's `subject`, giving one accumulator per agent, team, or
  run — the right scope for a signal reasoning about one thing.

  A signal that correlates *across* subjects must say so by returning a
  constant. A crash cascade is precisely the observation that several
  **different** agents failed; partitioned per agent it can never see more than
  one, and would silently never fire.

  This belongs to the signal, not the emitter. `agent.crashed` naturally carries
  the agent as its subject, and it should not have to know that some downstream
  signal wants to count across agents.
  """
  @callback partition_key(event :: Event.t()) :: String.t() | nil

  @doc "Initial state for one partition key."
  @callback init(key :: String.t() | nil) :: state()

  @doc "Fold an event into state. Called only for events matching `c:topics/0`."
  @callback handle_event(event :: Event.t(), state :: state()) :: state()

  @doc """
  Whether the accumulated state now means something.

  Asked after every event and on every timer tick. Must be cheap and must not
  have side effects — it is asked far more often than it answers true.
  """
  @callback ready?(state :: state(), trigger :: trigger()) :: boolean()

  @doc """
  The payload of the emitted event, or `nil` to emit nothing after all.

  Returning `nil` lets a signal decide at the last moment that the conclusion
  is not worth stating, without having to encode that in `c:ready?/2`.
  """
  @callback build_emission(state :: state()) :: map() | nil

  @doc "State after emitting. Usually clears the accumulation window."
  @callback reset(state :: state()) :: state()

  @doc """
  Handle a message that is not an event, e.g. a monitor going down.

  Defaulted to leaving state untouched, so a stray message cannot crash an
  accumulator that never asked for it.
  """
  @callback handle_info(message :: term(), state :: state()) :: state()

  @optional_callbacks [handle_info: 2, partition_key: 1]

  @doc """
  Bring in the behaviour with a working default for every callback.

  Override only what differs — most signals are the two or three callbacks that
  carry their actual reasoning.
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour Signals.Signal

      alias Signals.Event

      @impl true
      def name, do: __MODULE__ |> Module.split() |> List.last() |> Macro.underscore()

      @impl true
      def topics, do: []

      @impl true
      def partition_key(%Event{subject: subject}), do: subject

      @impl true
      def interval, do: Signals.Config.default_interval_ms()

      @impl true
      def init(key), do: %{key: key, events: []}

      @impl true
      def handle_event(%Event{} = event, state),
        do: %{state | events: [event | state.events]}

      @impl true
      def ready?(_state, _trigger), do: false

      @impl true
      def build_emission(%{events: []}), do: nil

      def build_emission(%{key: key, events: events}),
        do: %{key: key, count: length(events)}

      @impl true
      def reset(state), do: %{state | events: []}

      @impl true
      def handle_info(_message, state), do: state

      defoverridable name: 0,
                     topics: 0,
                     partition_key: 1,
                     interval: 0,
                     init: 1,
                     handle_event: 2,
                     ready?: 2,
                     build_emission: 1,
                     reset: 1,
                     handle_info: 2
    end
  end

  @doc """
  Whether a module implements this behaviour.

      iex> Signals.Signal.signal?(Signals.Examples.LoopDetected)
      true
      iex> Signals.Signal.signal?(Enum)
      false
  """
  @spec signal?(module()) :: boolean()
  def signal?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :name, 0) and
      function_exported?(module, :topics, 0) and function_exported?(module, :ready?, 2)
  end

  def signal?(_), do: false
end
