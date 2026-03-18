defmodule Ichor.Operator do
  @moduledoc """
  Unified operator messaging interface.

  Two delivery paths:
    1. BEAM-native: AgentProcess.send_message (GenServer.cast)
    2. Tmux direct: Registry metadata lookup -> Tmux.deliver

  Targets:
    - `"agent:<session_id>"` or `"session:<session_id>"` -- single agent
    - `"team:<name>"` -- all members of a team
    - `"fleet:all"` -- all active agents
    - raw session_id string -- treated as agent target
  """

  def start_message_log do
    Ichor.Fleet.Comms.start_message_log()
  end

  @doc "Read recent messages for the comms panel."
  @spec recent_messages(pos_integer()) :: [map()]
  defdelegate recent_messages(limit \\ 50), to: Ichor.Fleet.Comms

  @doc """
  Spawn a new agent in a tmux session with instruction overlay.

  Delegates to AgentSpawner. Returns `{:ok, agent_info}` or `{:error, reason}`.
  """
  defdelegate spawn_agent(opts), to: Ichor.AgentSpawner

  @doc """
  Stop a spawned agent by session name.
  """
  defdelegate stop_agent(session_name), to: Ichor.AgentSpawner

  @doc """
  Send a message to any target. Returns `{:ok, delivered_count}` or `{:error, reason}`.

  Uses BEAM-native AgentProcess delivery. Falls back to direct tmux delivery
  via Registry metadata when no BEAM process exists.
  """
  defdelegate send(target, content, opts \\ []), to: Ichor.Fleet.Comms
end
