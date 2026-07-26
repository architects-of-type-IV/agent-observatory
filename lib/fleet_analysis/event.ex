defmodule FleetAnalysis.Event do
  @moduledoc """
  The shape of an event this library reads, and tolerant accessors for it.

  Events are supplied by the host — an Ecto schema, an Ash resource, or a plain
  map. Rather than impose a struct, `FleetAnalysis` reads a documented set of
  fields and tolerates their absence.

  ## Fields

  | Field | Used for |
  |---|---|
  | `:inserted_at` | Ordering and every staleness calculation. Required. |
  | `:session_id` | Grouping events into sessions. Required. |
  | `:hook_event_type` | Classifying tool calls, failures, and session ends. |
  | `:source_app` | Fallback label for a session. |
  | `:tool_name` | Loop detection. |
  | `:payload` | Model lookup, via `payload["model"]`. |
  | `:model_name` | Model lookup fallback. |
  | `:cwd` | Working directory shown in topology. |
  | `:permission_mode` | Carried through to session summaries. |
  | `:tmux_session` | Matching sessions against live tmux sessions. |

  ## Event types

  `:hook_event_type` is matched against `:PreToolUse`, `:PostToolUse`,
  `:PostToolUseFailure`, and `:SessionEnd`. Other values are ignored rather
  than rejected, so a host can emit whatever else it likes.

  ## Why tolerant reads

  The original code used `e.payload["model"]` and `e.model_name` directly, which
  raises on any event map missing those keys. An analysis pass over a live event
  log is exactly where partial records show up — a truncated write, an older
  schema version, a test fixture. Crashing the dashboard over one malformed
  event is the wrong trade, so every read here falls back to `nil`.
  """

  @type t :: map()

  @doc """
  Read a field, returning `default` when it is missing.

  Works for maps with atom keys and for structs.

      iex> FleetAnalysis.Event.get(%{cwd: "/srv"}, :cwd)
      "/srv"

      iex> FleetAnalysis.Event.get(%{}, :cwd)
      nil
  """
  @spec get(t(), atom(), term()) :: term()
  def get(event, key, default \\ nil)
  def get(event, key, default) when is_map(event), do: Map.get(event, key, default) || default
  def get(_event, _key, default), do: default

  @doc """
  The timestamp an event was recorded at.

  Falls back to the Unix epoch when absent, so sorting never crashes on a
  partial record. A misordered event is a smaller problem than a dead page.
  """
  @spec timestamp(t()) :: DateTime.t()
  def timestamp(event) do
    case get(event, :inserted_at) do
      %DateTime{} = dt -> dt
      _ -> ~U[1970-01-01 00:00:00Z]
    end
  end

  @doc "The event type, or `nil`."
  @spec type(t()) :: atom() | nil
  def type(event), do: get(event, :hook_event_type)

  @doc """
  The model an event mentions, checking `payload["model"]` then `:model_name`.

      iex> FleetAnalysis.Event.model(%{payload: %{"model" => "claude-opus-5"}})
      "claude-opus-5"

      iex> FleetAnalysis.Event.model(%{model_name: "haiku"})
      "haiku"

      iex> FleetAnalysis.Event.model(%{})
      nil
  """
  @spec model(t()) :: String.t() | nil
  def model(event) do
    payload = get(event, :payload, %{})
    from_payload = if is_map(payload), do: Map.get(payload, "model"), else: nil

    from_payload || get(event, :model_name)
  end

  @doc "The first non-nil model across a list of events."
  @spec find_model([t()]) :: String.t() | nil
  def find_model(events), do: Enum.find_value(events, &model/1)

  @doc "The first non-nil working directory across a list of events."
  @spec find_cwd([t()]) :: String.t() | nil
  def find_cwd(events), do: Enum.find_value(events, &get(&1, :cwd))

  @doc "Sort events newest first."
  @spec newest_first([t()]) :: [t()]
  def newest_first(events), do: Enum.sort_by(events, &timestamp/1, {:desc, DateTime})
end
