defmodule Ichor.Infrastructure.AgentLifecycle do
  @moduledoc """
  Centralized lifecycle signal emission for agent processes.

  Wraps `Ichor.Signals.emit/2` calls behind named functions so that signal
  names and payload shapes are defined in one place.  Callers never need to
  know the wire names of lifecycle signals.

  All signals carry both `session_id` (administrative lookup key) and `name`
  (human-readable agent identity). Downstream consumers (Memories bridge,
  dashboard, watchdogs) should use `name` for display and entity extraction,
  `session_id` for addressing.
  """

  @doc "Emit the signal that announces a newly-started agent."
  @spec agent_started(String.t(), String.t(), atom(), String.t() | nil) :: :ok
  def agent_started(id, name, role, team) do
    Ichor.Signals.emit(:agent_started, %{session_id: id, name: name, role: role, team: team})
  end

  @doc "Emit the signal that announces a paused agent."
  @spec agent_paused(String.t(), String.t()) :: :ok
  def agent_paused(id, name) do
    Ichor.Signals.emit(:agent_paused, %{session_id: id, name: name})
  end

  @doc "Emit the signal that announces a resumed agent."
  @spec agent_resumed(String.t(), String.t()) :: :ok
  def agent_resumed(id, name) do
    Ichor.Signals.emit(:agent_resumed, %{session_id: id, name: name})
  end

  @doc "Emit the signal that announces a stopped agent, with the termination reason."
  @spec agent_stopped(String.t(), String.t(), term()) :: :ok
  def agent_stopped(id, name, reason) do
    Ichor.Signals.emit(:agent_stopped, %{session_id: id, name: name, reason: reason})
  end
end
