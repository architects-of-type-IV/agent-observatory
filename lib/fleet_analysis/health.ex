defmodule FleetAnalysis.Health do
  @moduledoc """
  Health of a single agent, derived from its events.

  Three failure modes, because they are the three that actually happen to
  long-running agents and none of them raise an error anywhere:

  **Stuck** — no events for longer than `stuck_after_sec`. The process is alive,
  the tmux pane is open, and nothing is happening. Only the event log shows it.

  **Looping** — the same tool called `loop_min_repeats` times in a row within
  the last `loop_window` events. The agent is busy and making no progress:
  re-reading a file it already read, retrying a command that will keep failing.
  Looks healthy by every liveness measure.

  **Failing** — a high ratio of failed tool calls. The agent is working and
  getting nowhere.

  ## Levels

    * `:unknown` — no events at all; nothing can be said
    * `:healthy`
    * `:warning` — failure rate above `failure_rate_warning`
    * `:critical` — stuck or looping

  Stuck and looping outrank failure rate, because they do not resolve on their
  own. A high failure rate often does.
  """

  alias FleetAnalysis.Config
  alias FleetAnalysis.Event

  @type level :: :unknown | :healthy | :warning | :critical

  @type issue ::
          {:stuck, Event.t()}
          | {:looping, [%{tool: term(), count: pos_integer()}]}
          | {:high_failure_rate, float()}

  @type t :: %{
          health: level(),
          issues: [issue()],
          failure_rate: float(),
          stuck?: boolean(),
          loops: [%{tool: term(), count: pos_integer()}]
        }

  @doc """
  Compute health for one agent's events.

  `now` is passed in rather than read from the clock so callers can analyse a
  historical window, and so tests are deterministic.
  """
  @spec compute([Event.t()], DateTime.t()) :: t()
  def compute(events, now \\ DateTime.utc_now())

  def compute([], _now) do
    %{health: :unknown, issues: [], failure_rate: 0.0, stuck?: false, loops: []}
  end

  def compute(events, now) do
    sorted = Event.newest_first(events)
    latest = List.first(sorted)

    stuck? = stuck?(latest, now)
    loops = detect_loops(sorted)
    failure_rate = failure_rate(events)

    %{
      health: classify(stuck?, loops, failure_rate),
      issues: issues(stuck?, loops, failure_rate, latest),
      failure_rate: failure_rate,
      stuck?: stuck?,
      loops: loops
    }
  end

  @doc """
  Ratio of failed tool calls to total tool calls, rounded to two places.

  Only `:PostToolUse` and `:PostToolUseFailure` count, so an agent that has not
  used any tools scores `0.0` rather than being penalised for idleness.

      iex> FleetAnalysis.Health.failure_rate([])
      0.0
  """
  @spec failure_rate([Event.t()]) :: float()
  def failure_rate(events) do
    tool_events = Enum.filter(events, &(Event.type(&1) in [:PostToolUse, :PostToolUseFailure]))

    case tool_events do
      [] ->
        0.0

      _ ->
        failures = Enum.count(tool_events, &(Event.type(&1) == :PostToolUseFailure))
        Float.round(failures / length(tool_events), 2)
    end
  end

  @doc """
  Runs of the same tool called consecutively in the recent window.

  Returns `[%{tool: name, count: n}]` for each run of at least
  `loop_min_repeats`. Only `:PreToolUse` events are considered, so a tool whose
  call and result both appear does not read as a repeat of itself.
  """
  @spec detect_loops([Event.t()]) :: [%{tool: term(), count: pos_integer()}]
  def detect_loops(sorted_events) do
    min_repeats = Config.loop_min_repeats()

    sorted_events
    |> Enum.take(Config.loop_window())
    |> Enum.filter(&(Event.type(&1) == :PreToolUse))
    |> Enum.map(&Event.get(&1, :tool_name))
    |> Enum.chunk_by(& &1)
    |> Enum.filter(&(length(&1) >= min_repeats))
    |> Enum.map(&%{tool: hd(&1), count: length(&1)})
  end

  @doc """
  Whether an agent has been silent past the stuck threshold.

  `nil` — no events — is not stuck; it is unknown.
  """
  @spec stuck?(Event.t() | nil, DateTime.t()) :: boolean()
  def stuck?(nil, _now), do: false

  def stuck?(latest, now) do
    DateTime.diff(now, Event.timestamp(latest), :second) > Config.stuck_after_sec()
  end

  defp classify(true, _loops, _rate), do: :critical
  defp classify(_stuck?, [_ | _], _rate), do: :critical

  defp classify(_stuck?, _loops, rate) do
    if rate > Config.failure_rate_warning(), do: :warning, else: :healthy
  end

  defp issues(stuck?, loops, failure_rate, latest) do
    []
    |> prepend(failure_rate > Config.failure_rate_critical(), {:high_failure_rate, failure_rate})
    |> prepend(loops != [], {:looping, loops})
    |> prepend(stuck?, {:stuck, latest})
  end

  defp prepend(list, true, item), do: [item | list]
  defp prepend(list, false, _item), do: list
end
