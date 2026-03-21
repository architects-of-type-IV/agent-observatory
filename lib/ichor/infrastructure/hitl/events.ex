defmodule Ichor.Infrastructure.HITL.Events do
  @moduledoc """
  Signal emission helpers for HITL lifecycle events.

  Wraps `Ichor.Signals.emit/2` and `Ichor.Signals.emit/3` behind named
  functions so that signal names and payload shapes are defined in one place.
  """

  @doc "Emit the signal that a session gate has been opened (paused)."
  @spec gate_open(String.t()) :: :ok
  def gate_open(session_id) do
    Ichor.Signals.emit(:gate_open, session_id, %{session_id: session_id})
  end

  @doc "Emit the signal that a session gate has been closed (unpaused or rejected)."
  @spec gate_close(String.t()) :: :ok
  def gate_close(session_id) do
    Ichor.Signals.emit(:gate_close, session_id, %{session_id: session_id})
  end

  @doc "Emit the signal that a buffered message has been logged for review."
  @spec decision_log(map()) :: :ok
  def decision_log(msg) do
    Ichor.Signals.emit(:decision_log, %{log: msg})
  end

  @doc "Emit the signal that an abandoned paused session was auto-released."
  @spec auto_released(String.t()) :: :ok
  def auto_released(session_id) do
    Ichor.Signals.emit(:hitl_auto_released, %{session_id: session_id})
  end
end
