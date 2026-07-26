defmodule Signals.Dedup do
  @moduledoc """
  A bounded set of recently seen event identities.

  Folding the same event twice is not a crash. It is a crash-rate signal firing
  at two crashes instead of five, a budget exhausted early, a cascade declared
  from one agent counted three times — quietly wrong, and still looking like it
  works. So the guard has to be reliable rather than best-effort.

  ## Identity, not position

  The key is `{source, id}`, which CloudEvents already requires producers to
  make unique per event. That works for every event from every producer,
  regardless of ordering, and needs no coordination.

  A monotonic log position cannot do this job:

    * events that carry no position — from a browser, a clock, a PubSub
      broadcast — would get no protection at all
    * with more than one producer, positions arrive out of order, and
      "discard anything at or below the high-water mark" permanently drops
      legitimate events that happen to arrive late

  Position remains useful for deciding *where to resume a replay*. That is a
  different question from *have I already folded this*, and answering both with
  one number gets one of them wrong.

  ## Bounded

  Only the most recent `limit` identities are kept. An accumulator reasons over
  a window — the last few tool calls, the last minute of crashes — so a
  redelivery arriving long after that window has nothing left to corrupt.
  Unbounded, this would be a slow memory leak on a process designed to run for
  the life of the fleet.
  """

  @enforce_keys [:limit]
  defstruct set: MapSet.new(), queue: [], size: 0, limit: 256

  @type key :: {String.t(), String.t()}
  @type t :: %__MODULE__{
          set: MapSet.t(),
          queue: [key()],
          size: non_neg_integer(),
          limit: pos_integer()
        }

  @doc """
  A new tracker holding at most `limit` identities.

      iex> Signals.Dedup.new(4) |> Signals.Dedup.size()
      0
  """
  @spec new(pos_integer()) :: t()
  def new(limit \\ 256), do: %__MODULE__{limit: limit}

  @doc """
  The identity of an event: `{source, id}`.

      iex> Signals.Dedup.key(Signals.Event.new("a.b", id: "e1", source: "backend"))
      {"backend", "e1"}
  """
  @spec key(Signals.Event.t()) :: key()
  def key(%Signals.Event{source: source, id: id}), do: {source, id}

  @doc """
  Whether this event has already been folded.

      iex> d = Signals.Dedup.new(4)
      iex> e = Signals.Event.new("a.b", id: "e1")
      iex> Signals.Dedup.seen?(d, e)
      false
      iex> d |> Signals.Dedup.put(e) |> Signals.Dedup.seen?(e)
      true
  """
  @spec seen?(t(), Signals.Event.t()) :: boolean()
  def seen?(%__MODULE__{set: set}, event), do: MapSet.member?(set, key(event))

  @doc """
  Record an event as folded, evicting the oldest identity past the limit.

      iex> ids = ["e1", "e2", "e3", "e4", "e5"]
      iex> d = Enum.reduce(ids, Signals.Dedup.new(3), fn id, acc ->
      ...>   Signals.Dedup.put(acc, Signals.Event.new("a.b", id: id))
      ...> end)
      iex> Signals.Dedup.size(d)
      3
      iex> Signals.Dedup.seen?(d, Signals.Event.new("a.b", id: "e1"))
      false
      iex> Signals.Dedup.seen?(d, Signals.Event.new("a.b", id: "e5"))
      true
  """
  @spec put(t(), Signals.Event.t()) :: t()
  def put(%__MODULE__{} = dedup, event) do
    k = key(event)

    if MapSet.member?(dedup.set, k) do
      dedup
    else
      %{dedup | set: MapSet.put(dedup.set, k), queue: [k | dedup.queue], size: dedup.size + 1}
      |> evict()
    end
  end

  @doc "How many identities are currently held."
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{size: size}), do: size

  defp evict(%__MODULE__{size: size, limit: limit} = dedup) when size <= limit, do: dedup

  defp evict(%__MODULE__{} = dedup) do
    {oldest, rest} = dedup.queue |> Enum.reverse() |> List.pop_at(0)

    %{
      dedup
      | set: MapSet.delete(dedup.set, oldest),
        queue: Enum.reverse(rest),
        size: dedup.size - 1
    }
  end
end
