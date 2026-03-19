defmodule Ichor.Operator do
  @moduledoc """
  Operator facade. Manages agent spawning and message log access.
  Messaging goes through Ichor.MessageRouter directly -- Operator no longer owns send.
  """

  alias Ichor.AgentSpawner
  alias Ichor.MessageRouter

  def start_message_log, do: MessageRouter.start_message_log()

  @spec recent_messages(pos_integer()) :: [map()]
  defdelegate recent_messages(limit \\ 50), to: MessageRouter

  @doc "Spawn a new agent in a tmux session with instruction overlay."
  defdelegate spawn_agent(opts), to: AgentSpawner

  @doc "Stop a spawned agent by session name."
  defdelegate stop_agent(session_name), to: AgentSpawner
end
