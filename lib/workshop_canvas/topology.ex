defmodule WorkshopCanvas.Topology do
  @moduledoc """
  Ordering and graph queries over the canvas's spawn links.

  Spawn links form a parent/child forest: a link `%{from: 1, to: 2}` means slot 1
  starts slot 2. Launching in the wrong order means a child comes up with no
  parent to report to, so `spawn_order/2` is what turns a drawing into a
  startup sequence.
  """

  @typedoc "An agent slot; only `:id` is required here."
  @type agent :: %{required(:id) => integer(), optional(any) => any}

  @typedoc "A parent/child spawn link between two slots."
  @type link :: %{required(:from) => integer(), required(:to) => integer(), optional(any) => any}

  @doc """
  Agents in depth-first spawn order: every parent before its children.

  Agents with no parent come first, each followed immediately by its subtree.

      iex> agents = [%{id: 1}, %{id: 2}, %{id: 3}]
      iex> links = [%{from: 1, to: 2}, %{from: 2, to: 3}]
      iex> WorkshopCanvas.Topology.spawn_order(agents, links) |> Enum.map(& &1.id)
      [1, 2, 3]

  ## Cycles and diamonds

  A canvas is drawn by hand, so it is not guaranteed to be a tree. Two cases
  need care, and getting them wrong is worse than the drawing being odd:

    * a **cycle** would make a naive walk recurse forever
    * a **diamond** — two parents, one child — would emit the child twice, and
      launching an agent twice is a real failure

  Both are handled by tracking what has already been emitted. Anything left over
  — a node reachable only inside a cycle — is appended in its original order, so
  every agent is launched exactly once even when the graph is nonsense.

      iex> agents = [%{id: 1}, %{id: 2}]
      iex> links = [%{from: 1, to: 2}, %{from: 2, to: 1}]
      iex> WorkshopCanvas.Topology.spawn_order(agents, links) |> Enum.map(& &1.id)
      [1, 2]
  """
  @spec spawn_order([agent()], [link()]) :: [agent()]
  def spawn_order(agents, spawn_links) do
    by_id = Map.new(agents, &{&1.id, &1})
    children = Enum.group_by(spawn_links, & &1.from, & &1.to)
    parented = MapSet.new(spawn_links, & &1.to)

    roots = Enum.reject(agents, &MapSet.member?(parented, &1.id))

    {ordered, seen} = walk(roots, by_id, children, {[], MapSet.new()})

    # A node only reachable through a cycle has no root to be found from, and
    # would otherwise be dropped from the launch entirely.
    unreachable = Enum.reject(agents, &MapSet.member?(seen, &1.id))

    Enum.reverse(ordered) ++ unreachable
  end

  @doc """
  The slot ids a spawn link graph never launches from a root.

  Non-empty means the drawing has a cycle. Useful for warning before launch
  rather than discovering it in the ordering.

      iex> WorkshopCanvas.Topology.unreachable([%{id: 1}, %{id: 2}], [%{from: 1, to: 2}])
      []

      iex> WorkshopCanvas.Topology.unreachable([%{id: 1}], [%{from: 1, to: 1}])
      [1]
  """
  @spec unreachable([agent()], [link()]) :: [integer()]
  def unreachable(agents, spawn_links) do
    by_id = Map.new(agents, &{&1.id, &1})
    children = Enum.group_by(spawn_links, & &1.from, & &1.to)
    parented = MapSet.new(spawn_links, & &1.to)

    roots = Enum.reject(agents, &MapSet.member?(parented, &1.id))
    {_ordered, seen} = walk(roots, by_id, children, {[], MapSet.new()})

    agents |> Enum.reject(&MapSet.member?(seen, &1.id)) |> Enum.map(& &1.id)
  end

  @doc """
  Direct children of a slot.

      iex> WorkshopCanvas.Topology.children_of(1, [%{from: 1, to: 2}, %{from: 1, to: 3}])
      [2, 3]
  """
  @spec children_of(integer(), [link()]) :: [integer()]
  def children_of(id, spawn_links) do
    spawn_links |> Enum.filter(&(&1.from == id)) |> Enum.map(& &1.to)
  end

  # Depth-first with an explicit worklist. `seen` guards both recursion into a
  # cycle and re-emitting a node with two parents.
  defp walk([], _by_id, _children, acc), do: acc

  defp walk([agent | rest], by_id, children, {ordered, seen}) do
    if MapSet.member?(seen, agent.id) do
      walk(rest, by_id, children, {ordered, seen})
    else
      kids =
        children
        |> Map.get(agent.id, [])
        |> Enum.map(&Map.get(by_id, &1))
        |> Enum.reject(&is_nil/1)

      walk(kids ++ rest, by_id, children, {[agent | ordered], MapSet.put(seen, agent.id)})
    end
  end
end
