defmodule Signals.DedupTest do
  use ExUnit.Case, async: true

  alias Signals.Dedup
  alias Signals.Event

  doctest Signals.Dedup

  defp event(id, opts \\ []), do: Event.new("a.b", Keyword.put(opts, :id, id))

  describe "identity" do
    test "keys on source and id together" do
      assert Dedup.key(event("e1", source: "backend")) == {"backend", "e1"}
    end

    test "the same id from different sources is two events" do
      dedup = Dedup.new(8) |> Dedup.put(event("e1", source: "backend"))

      refute Dedup.seen?(dedup, event("e1", source: "frontend"))
    end
  end

  describe "seen?/2" do
    test "a fresh tracker has seen nothing" do
      refute Dedup.seen?(Dedup.new(8), event("e1"))
    end

    test "recognises a recorded event" do
      assert Dedup.new(8) |> Dedup.put(event("e1")) |> Dedup.seen?(event("e1"))
    end

    test "does not confuse distinct events" do
      dedup = Dedup.new(8) |> Dedup.put(event("e1"))

      refute Dedup.seen?(dedup, event("e2"))
    end
  end

  describe "put/2" do
    test "is idempotent — recording twice does not consume two slots" do
      dedup = Dedup.new(8) |> Dedup.put(event("e1")) |> Dedup.put(event("e1"))

      assert Dedup.size(dedup) == 1
    end

    test "grows up to the limit" do
      dedup =
        Enum.reduce(1..5, Dedup.new(8), fn n, acc -> Dedup.put(acc, event("e#{n}")) end)

      assert Dedup.size(dedup) == 5
    end

    test "never exceeds the limit" do
      dedup =
        Enum.reduce(1..100, Dedup.new(10), fn n, acc -> Dedup.put(acc, event("e#{n}")) end)

      assert Dedup.size(dedup) == 10
    end

    test "evicts oldest first" do
      dedup =
        Enum.reduce(1..12, Dedup.new(3), fn n, acc -> Dedup.put(acc, event("e#{n}")) end)

      refute Dedup.seen?(dedup, event("e9"))
      assert Dedup.seen?(dedup, event("e10"))
      assert Dedup.seen?(dedup, event("e11"))
      assert Dedup.seen?(dedup, event("e12"))
    end

    test "a limit of one keeps only the most recent" do
      dedup = Dedup.new(1) |> Dedup.put(event("e1")) |> Dedup.put(event("e2"))

      refute Dedup.seen?(dedup, event("e1"))
      assert Dedup.seen?(dedup, event("e2"))
    end
  end

  describe "what position-based dedup got wrong" do
    test "events carrying no position are still deduplicated" do
      # A browser click or a clock tick has no log position. Position-based
      # dedup gave these no protection at all.
      e = event("e1")
      refute Event.position(e)

      assert Dedup.new(8) |> Dedup.put(e) |> Dedup.seen?(e)
    end

    test "an out-of-order arrival is not discarded" do
      # Position-based dedup discarded anything at or below a high-water mark,
      # so a late event with a lower position was dropped forever.
      late = event("late") |> Event.with_position(5)
      early = event("early") |> Event.with_position(10)

      dedup = Dedup.new(8) |> Dedup.put(early)

      refute Dedup.seen?(dedup, late)
    end

    test "identity survives events sharing a position" do
      # Two producers can independently assign the same position.
      a = event("a") |> Event.with_position(1)
      b = event("b") |> Event.with_position(1)

      dedup = Dedup.new(8) |> Dedup.put(a)

      assert Dedup.seen?(dedup, a)
      refute Dedup.seen?(dedup, b)
    end
  end
end
