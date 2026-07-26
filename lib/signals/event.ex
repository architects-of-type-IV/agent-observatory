defmodule Signals.Event do
  @moduledoc """
  The atom: one thing that happened, in a CloudEvents-shaped envelope.

  Events are individually unremarkable — a tool completed, a pane went quiet, a
  clock ticked. Meaning is not in the event. Meaning is what a `Signals.Signal`
  builds by watching several of them.

  ## CloudEvents

  The attribute names follow [CloudEvents v1.0.2](https://cloudevents.io) rather
  than inventing a private envelope, so events can cross a process, a node, or a
  broker without translation.

  | Attribute | Holds |
  |---|---|
  | `type` | The topic, dot-delimited big-to-small: `agent.tool.completed` |
  | `source` | What produced it: `"backend"`, `"frontend"`, `"temporal"`, or a URI |
  | `subject` | The partition key — what this event is about |
  | `id` | Unique per event; the dedup key |
  | `time` | When it happened |
  | `data` | The payload |

  `subject` is load-bearing beyond description: it is the default partition key,
  so all events about one thing reach one accumulator in order.

  ## Extensions

  CloudEvents allows extension attributes. Two matter here:

    * `position` — monotonic position in the durable log, used for checkpointing
      and for discarding replays an accumulator has already folded in
    * `correlation_id` / `causation_id` — provenance across a chain

  ## Topic naming

  Big to small, so prefix wildcards select coherently:

      agent.tool.budget.exhausted    good
      agent.session.started          good
      ToolBudgetExceededEvent        bad
      new_event                      bad — framework noise, not a domain fact
  """

  @specversion "1.0"

  @enforce_keys [:id, :type, :source, :time]
  defstruct [
    :id,
    :type,
    :source,
    :subject,
    :time,
    :data,
    specversion: @specversion,
    extensions: %{}
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          type: String.t(),
          source: String.t(),
          subject: String.t() | nil,
          time: DateTime.t(),
          data: map() | nil,
          specversion: String.t(),
          extensions: map()
        }

  @doc """
  Build an event.

      iex> e = Signals.Event.new("agent.tool.completed", subject: "agent-1", data: %{tool: "Read"})
      iex> {e.type, e.subject, e.source}
      {"agent.tool.completed", "agent-1", "backend"}

  ## Options

    * `:subject` — partition key
    * `:source` — defaults to `Signals.Config.default_source/0`
    * `:data`, `:time`, `:id`, `:extensions`
  """
  @spec new(String.t(), keyword()) :: t()
  def new(type, opts \\ []) when is_binary(type) do
    %__MODULE__{
      id: Keyword.get(opts, :id) || generate_id(),
      type: type,
      source: Keyword.get(opts, :source) || Signals.Config.default_source(),
      subject: Keyword.get(opts, :subject),
      time: Keyword.get(opts, :time) || DateTime.utc_now(),
      data: Keyword.get(opts, :data),
      extensions: Keyword.get(opts, :extensions, %{})
    }
  end

  @doc """
  The log position, or `nil` when the event is not from a durable log.

      iex> Signals.Event.new("a.b", extensions: %{position: 7}) |> Signals.Event.position()
      7
  """
  @spec position(t()) :: integer() | nil
  def position(%__MODULE__{extensions: ext}), do: Map.get(ext, :position)

  @doc "Return a copy carrying a log position."
  @spec with_position(t(), integer()) :: t()
  def with_position(%__MODULE__{extensions: ext} = event, position),
    do: %{event | extensions: Map.put(ext, :position, position)}

  @doc """
  Whether this event is itself a signal emission.

      iex> Signals.Event.emission?(Signals.Event.new("signal.loop_detected"))
      true
      iex> Signals.Event.emission?(Signals.Event.new("agent.tool.completed"))
      false
  """
  @spec emission?(t()) :: boolean()
  def emission?(%__MODULE__{type: type}), do: String.starts_with?(type, prefix())

  @doc """
  The signal name an emission carries, or `nil`.

      iex> Signals.Event.new("signal.loop_detected") |> Signals.Event.signal_name()
      "loop_detected"
  """
  @spec signal_name(t()) :: String.t() | nil
  def signal_name(%__MODULE__{type: type}) do
    case String.split(type, prefix(), parts: 2) do
      ["", name] -> name
      _ -> nil
    end
  end

  @doc """
  Render as a plain CloudEvents map with string keys, for the wire.

  Extensions are flattened to top level, which is where CloudEvents puts them.
  """
  @spec to_cloudevent(t()) :: map()
  def to_cloudevent(%__MODULE__{} = event) do
    base = %{
      "specversion" => event.specversion,
      "id" => event.id,
      "type" => event.type,
      "source" => event.source,
      "time" => DateTime.to_iso8601(event.time)
    }

    base
    |> put_unless_nil("subject", event.subject)
    |> put_unless_nil("data", event.data)
    |> Map.merge(Map.new(event.extensions, fn {k, v} -> {to_string(k), v} end))
  end

  @doc """
  Parse a CloudEvents map. Unknown top-level keys become extensions.

      iex> {:ok, e} = Signals.Event.from_cloudevent(%{
      ...>   "id" => "1", "type" => "a.b", "source" => "x",
      ...>   "time" => "2026-01-01T00:00:00Z", "position" => 3
      ...> })
      iex> {e.type, Signals.Event.position(e)}
      {"a.b", 3}
  """
  @spec from_cloudevent(map()) :: {:ok, t()} | {:error, term()}
  def from_cloudevent(map) when is_map(map) do
    with {:ok, id} <- fetch(map, "id"),
         {:ok, type} <- fetch(map, "type"),
         {:ok, source} <- fetch(map, "source"),
         {:ok, time} <- parse_time(Map.get(map, "time")) do
      known = ~w(specversion id type source subject time data datacontenttype dataschema)

      {:ok,
       %__MODULE__{
         id: id,
         type: type,
         source: source,
         subject: Map.get(map, "subject"),
         time: time,
         data: Map.get(map, "data"),
         specversion: Map.get(map, "specversion", @specversion),
         extensions: map |> Map.drop(known) |> Map.new(fn {k, v} -> {atomize(k), v} end)
       }}
    end
  end

  def from_cloudevent(_), do: {:error, :not_a_map}

  defp prefix, do: Signals.Config.emission_prefix()

  defp fetch(map, key) do
    case Map.get(map, key) do
      nil -> {:error, {:missing, key}}
      value -> {:ok, value}
    end
  end

  defp parse_time(nil), do: {:ok, DateTime.utc_now()}
  defp parse_time(%DateTime{} = dt), do: {:ok, dt}

  defp parse_time(binary) when is_binary(binary) do
    case DateTime.from_iso8601(binary) do
      {:ok, dt, _offset} -> {:ok, dt}
      {:error, reason} -> {:error, reason}
    end
  end

  defp put_unless_nil(map, _key, nil), do: map
  defp put_unless_nil(map, key, value), do: Map.put(map, key, value)

  defp atomize(key) when is_atom(key), do: key

  defp atomize(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> key
  end

  defp generate_id, do: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
end
