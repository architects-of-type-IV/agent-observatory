defmodule WorkshopCanvas.TopologyTest do
  use ExUnit.Case, async: true

  alias WorkshopCanvas.Topology

  doctest WorkshopCanvas.Topology

  defp ids(agents), do: Enum.map(agents, & &1.id)
  defp agents(n), do: for(i <- 1..n, do: %{id: i})

  describe "spawn_order/2" do
    test "a chain comes out parent first" do
      links = [%{from: 1, to: 2}, %{from: 2, to: 3}]

      assert ids(Topology.spawn_order(agents(3), links)) == [1, 2, 3]
    end

    test "unlinked agents keep their original order" do
      assert ids(Topology.spawn_order(agents(3), [])) == [1, 2, 3]
    end

    test "a parent precedes all of its children" do
      links = [%{from: 1, to: 2}, %{from: 1, to: 3}]

      order = ids(Topology.spawn_order(agents(3), links))

      assert hd(order) == 1
      assert Enum.sort(order) == [1, 2, 3]
    end

    test "walks depth first, so a subtree completes before the next root" do
      #   1 -> 2 -> 3     4 (separate root)
      agents = agents(4)
      links = [%{from: 1, to: 2}, %{from: 2, to: 3}]

      assert ids(Topology.spawn_order(agents, links)) == [1, 2, 3, 4]
    end

    test "several roots each bring their own subtree" do
      agents = agents(4)
      links = [%{from: 1, to: 2}, %{from: 3, to: 4}]

      assert ids(Topology.spawn_order(agents, links)) == [1, 2, 3, 4]
    end

    test "an empty canvas orders to nothing" do
      assert Topology.spawn_order([], []) == []
    end

    test "a link naming a slot that does not exist is skipped" do
      links = [%{from: 1, to: 99}]

      assert ids(Topology.spawn_order(agents(2), links)) == [1, 2]
    end
  end

  describe "spawn_order/2 with a diamond" do
    test "a child with two parents is launched once, not twice" do
      # 1 -> 3, 2 -> 3. Launching an agent twice is a real failure.
      agents = agents(3)
      links = [%{from: 1, to: 3}, %{from: 2, to: 3}]

      order = ids(Topology.spawn_order(agents, links))

      assert Enum.sort(order) == [1, 2, 3]
      assert length(order) == 3
    end

    test "the shared child still comes after a parent" do
      agents = agents(3)
      links = [%{from: 1, to: 3}, %{from: 2, to: 3}]

      order = ids(Topology.spawn_order(agents, links))

      assert Enum.find_index(order, &(&1 == 3)) > Enum.find_index(order, &(&1 == 1))
    end
  end

  describe "spawn_order/2 with a cycle" do
    test "terminates instead of recursing forever" do
      agents = agents(2)
      links = [%{from: 1, to: 2}, %{from: 2, to: 1}]

      assert Enum.sort(ids(Topology.spawn_order(agents, links))) == [1, 2]
    end

    test "a self-link terminates" do
      assert ids(Topology.spawn_order([%{id: 1}], [%{from: 1, to: 1}])) == [1]
    end

    test "every agent is still launched exactly once" do
      # A cycle leaves no root, so a naive root-first walk drops all of them.
      agents = agents(3)
      links = [%{from: 1, to: 2}, %{from: 2, to: 3}, %{from: 3, to: 1}]

      order = ids(Topology.spawn_order(agents, links))

      assert Enum.sort(order) == [1, 2, 3]
    end

    test "agents outside the cycle are still ordered normally" do
      agents = agents(4)
      links = [%{from: 1, to: 2}, %{from: 2, to: 1}, %{from: 3, to: 4}]

      order = ids(Topology.spawn_order(agents, links))

      assert Enum.sort(order) == [1, 2, 3, 4]
      assert Enum.find_index(order, &(&1 == 3)) < Enum.find_index(order, &(&1 == 4))
    end
  end

  describe "unreachable/2" do
    test "a clean tree has none" do
      assert Topology.unreachable(agents(3), [%{from: 1, to: 2}, %{from: 2, to: 3}]) == []
    end

    test "reports the members of a cycle" do
      links = [%{from: 1, to: 2}, %{from: 2, to: 1}]

      assert Enum.sort(Topology.unreachable(agents(2), links)) == [1, 2]
    end

    test "reports a self-link" do
      assert Topology.unreachable([%{id: 1}], [%{from: 1, to: 1}]) == [1]
    end

    test "an isolated agent is reachable, being its own root" do
      assert Topology.unreachable(agents(2), []) == []
    end
  end

  describe "children_of/2" do
    test "lists direct children only" do
      links = [%{from: 1, to: 2}, %{from: 1, to: 3}, %{from: 2, to: 4}]

      assert Topology.children_of(1, links) == [2, 3]
      assert Topology.children_of(2, links) == [4]
    end

    test "a leaf has none" do
      assert Topology.children_of(9, [%{from: 1, to: 2}]) == []
    end
  end
end
