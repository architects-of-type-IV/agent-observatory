defmodule FleetAnalysis.Topology do
  @moduledoc """
  Renderable nodes and edges for a fleet graph.

  Combines two sources that overlap but neither of which is complete:

    * **Sessions** — what is actually running, from the event log
    * **Teams** — what was *supposed* to run, from the team configuration

  A member configured but never started has no session, and a session running
  outside any team has no member. Both belong on the graph, so this emits a node
  per session plus a node for every team member with no session of its own. The
  gap between the two is usually the interesting part: a member node with no
  session is an agent that failed to start.
  """

  alias FleetAnalysis.Config
  alias FleetAnalysis.Entry
  alias FleetAnalysis.Event

  @typedoc "A graph node."
  @type node_t :: %{
          trace_id: String.t(),
          agent_id: String.t(),
          state: String.t(),
          label: String.t() | nil,
          model: String.t() | nil,
          team: String.t() | nil,
          events: non_neg_integer(),
          cwd: String.t() | nil,
          duration: String.t() | nil
        }

  @typedoc "A graph edge."
  @type edge :: %{
          from: String.t(),
          to: String.t(),
          traffic_volume: non_neg_integer(),
          latency_ms: non_neg_integer(),
          status: String.t()
        }

  @doc """
  Build `{nodes, edges}` from derived sessions and team records.

  Teams are maps with `:name` and `:members`; each member is a map read through
  `Access`, with `:agent_id`, and optionally `:name`, `:agent_type`, `:status`,
  `:model`, `:event_count`, and `:cwd`.
  """
  @spec build([map()], [map()], DateTime.t()) :: {[node_t()], [edge()]}
  def build(sessions, teams, now \\ DateTime.utc_now()) do
    member_index = member_index(teams)
    session_ids = MapSet.new(sessions, & &1.session_id)

    session_nodes = Enum.map(sessions, &session_node(&1, now, member_index))
    orphan_nodes = Enum.flat_map(teams, &member_nodes(&1, session_ids))

    {session_nodes ++ orphan_nodes, Enum.flat_map(teams, &team_edges/1)}
  end

  @doc """
  Classify a session as `"dead"`, `"idle"`, or `"active"`.

      iex> FleetAnalysis.Topology.state(%{ended?: true}, DateTime.utc_now())
      "dead"
  """
  @spec state(map(), DateTime.t()) :: String.t()
  def state(%{ended?: true}, _now), do: "dead"

  def state(session, now) do
    last = Event.timestamp(Map.get(session, :latest_event, %{}))

    if DateTime.diff(now, last, :second) > Config.idle_after_sec(), do: "idle", else: "active"
  end

  @doc """
  Render a duration in seconds compactly.

      iex> FleetAnalysis.Topology.duration(45)
      "45s"

      iex> FleetAnalysis.Topology.duration(90)
      "1m"

      iex> FleetAnalysis.Topology.duration(3_725)
      "1h2m"
  """
  @spec duration(integer()) :: String.t()
  def duration(sec) when sec < 60, do: "#{sec}s"
  def duration(sec) when sec < 3600, do: "#{div(sec, 60)}m"
  def duration(sec), do: "#{div(sec, 3600)}h#{rem(div(sec, 60), 60)}m"

  @doc """
  Shorten a model identifier to its family.

      iex> FleetAnalysis.Topology.short_model("claude-opus-5")
      "opus"

      iex> FleetAnalysis.Topology.short_model("gpt-4o")
      "gpt"

      iex> FleetAnalysis.Topology.short_model(nil)
      nil
  """
  @spec short_model(String.t() | nil) :: String.t() | nil
  def short_model(nil), do: nil

  def short_model(model) when is_binary(model) do
    cond do
      String.contains?(model, "opus") -> "opus"
      String.contains?(model, "sonnet") -> "sonnet"
      String.contains?(model, "haiku") -> "haiku"
      true -> model |> String.split("-") |> List.first() || model
    end
  end

  def short_model(_), do: nil

  # Private

  defp member_index(teams) do
    for team <- teams,
        member <- members(team),
        id = member[:agent_id],
        into: %{} do
      {id, %{team: Map.get(team, :name), role: member[:name] || member[:agent_type]}}
    end
  end

  defp session_node(session, now, member_index) do
    info = Map.get(member_index, session.session_id, %{})
    started = Event.timestamp(Map.get(session, :first_event, %{}))

    %{
      trace_id: session.session_id,
      agent_id: session.session_id,
      state: state(session, now),
      label: info[:role] || session.source_app || Entry.short_id(session.session_id),
      model: short_model(Map.get(session, :model)),
      team: info[:team],
      events: Map.get(session, :event_count, 0),
      cwd: basename(Map.get(session, :cwd)),
      duration: duration(DateTime.diff(now, started, :second))
    }
  end

  # A member with a live session already has a node; emitting a second one would
  # double-count it on the graph.
  defp member_nodes(team, session_ids) do
    for member <- members(team),
        id = member[:agent_id],
        not MapSet.member?(session_ids, id) do
      %{
        trace_id: id,
        agent_id: id,
        state: to_string(member[:status] || :idle),
        label: member[:name] || member[:agent_type] || Entry.short_id(id),
        model: short_model(member[:model]),
        team: Map.get(team, :name),
        events: member[:event_count] || 0,
        cwd: basename(member[:cwd]),
        duration: nil
      }
    end
  end

  defp team_edges(team) do
    team
    |> members()
    |> Enum.map(& &1[:agent_id])
    |> Enum.reject(&is_nil/1)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [from, to] ->
      %{from: from, to: to, traffic_volume: 0, latency_ms: 0, status: "active"}
    end)
  end

  defp members(team) do
    case Map.get(team, :members) do
      members when is_list(members) -> members
      _ -> []
    end
  end

  defp basename(nil), do: nil
  defp basename(path) when is_binary(path), do: Path.basename(path)
  defp basename(_), do: nil
end
