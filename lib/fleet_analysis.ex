defmodule FleetAnalysis do
  @moduledoc """
  Derives health, sessions, and topology from a fleet's raw event log.

  Extracted from the ICHOR IV agent observatory. Pure functions over event
  lists — no processes, no storage, no clock of its own. Every entry point takes
  `now` as an argument, so you can analyse a historical window and tests are
  deterministic.

  ## What it computes

  | Module | From | To |
  |---|---|---|
  | `FleetAnalysis.Health` | one agent's events | stuck / looping / failing |
  | `FleetAnalysis.Sessions` | all events | session summaries |
  | `FleetAnalysis.Topology` | sessions + teams | graph nodes and edges |
  | `FleetAnalysis.Entry` | — | id and role helpers |

  ## Why derive rather than store

  Sessions are inferred by grouping the append-only event log, not read from a
  session table. A separately maintained table can disagree with what actually
  happened; a derivation cannot.

  ## The failure modes worth naming

  A stuck agent and a looping agent both look perfectly healthy from outside:
  the process is up, the pane is open, the supervisor is content. Neither raises
  anything. They are only visible as *shapes in the event log* — a gap, or a
  repeat — which is why this is a library and not a supervisor callback.

  ## Events

  Events are whatever the host already has: Ecto schemas, Ash resources, or
  plain maps. `FleetAnalysis.Event` documents the fields read and tolerates
  every one of them being absent.

  ## Example

      events = MyApp.Events.recent()
      now = DateTime.utc_now()

      FleetAnalysis.health(agent_events, now)
      #=> %{health: :critical, issues: [{:stuck, event}], failure_rate: 0.0, ...}

      sessions = FleetAnalysis.sessions(events, tmux: TmuxChannel.list_sessions())
      {nodes, edges} = FleetAnalysis.topology(sessions, MyApp.Teams.all(), now)
  """

  alias FleetAnalysis.Health
  alias FleetAnalysis.Sessions
  alias FleetAnalysis.Topology

  @doc "Health for one agent's events. See `FleetAnalysis.Health.compute/2`."
  @spec health([map()], DateTime.t()) :: Health.t()
  defdelegate health(events, now \\ DateTime.utc_now()), to: Health, as: :compute

  @doc "Session summaries from raw events. See `FleetAnalysis.Sessions.active_sessions/2`."
  @spec sessions([map()], keyword()) :: [Sessions.session()]
  defdelegate sessions(events, opts \\ []), to: Sessions, as: :active_sessions

  @doc "Graph nodes and edges. See `FleetAnalysis.Topology.build/3`."
  @spec topology([map()], [map()], DateTime.t()) :: {[Topology.node_t()], [Topology.edge()]}
  defdelegate topology(sessions, teams, now \\ DateTime.utc_now()), to: Topology, as: :build

  @doc """
  Health for every session in one pass, keyed by session id.

  Groups the events once and analyses each group, rather than making the caller
  filter the whole log per agent.
  """
  @spec health_by_session([map()], DateTime.t()) :: %{optional(String.t()) => Health.t()}
  def health_by_session(events, now \\ DateTime.utc_now()) do
    events
    |> Enum.group_by(&FleetAnalysis.Event.get(&1, :session_id))
    |> Map.delete(nil)
    |> Map.new(fn {session_id, group} -> {session_id, Health.compute(group, now)} end)
  end

  @doc """
  Session ids whose health is `:critical` or `:warning`, worst first.

  The one-call answer to "what needs attention right now".
  """
  @spec unhealthy([map()], DateTime.t()) :: [{String.t(), Health.t()}]
  def unhealthy(events, now \\ DateTime.utc_now()) do
    events
    |> health_by_session(now)
    |> Enum.filter(fn {_id, health} -> health.health in [:critical, :warning] end)
    |> Enum.sort_by(fn {_id, health} -> severity(health.health) end)
  end

  defp severity(:critical), do: 0
  defp severity(:warning), do: 1
  defp severity(_), do: 2
end
