defmodule Ichor.Signals.EventStream.AgentLifecycle do
  @moduledoc """
  Signal emission helper for hook-originated fleet lifecycle events.

  Translates raw hook event data into Signals-domain signals. Infrastructure
  subscribers react to those signals to perform the actual fleet mutations
  (spawn/terminate AgentProcess, create/disband TeamSupervisor).

  This module must NOT alias or import any Infrastructure module.
  """

  require Logger

  alias Ichor.Signals

  # ETS table names -- must match the constants declared in EventStream.
  @table :event_buffer_events
  @aliases :ichor_session_aliases

  @doc """
  Resolve or create an AgentProcess for the given session_id and event.

  Returns the canonical agent id to use for subsequent operations.
  """
  @spec resolve_or_create_agent(String.t(), map()) :: String.t()
  def resolve_or_create_agent(session_id, event) do
    cond do
      session_known?(session_id) ->
        session_id

      match = find_agent_by_tmux(event.tmux_session) ->
        match

      true ->
        emit_session_started(session_id, event)
        session_id
    end
  rescue
    _ -> session_id
  end

  @doc "Look up an existing agent by its tmux session name. Returns agent id or nil."
  @spec find_agent_by_tmux(String.t() | nil) :: String.t() | nil
  def find_agent_by_tmux(nil), do: nil
  def find_agent_by_tmux(""), do: nil

  def find_agent_by_tmux(tmux_session) do
    # @aliases stores {uuid_id, tmux_session_name} entries.
    # Find a uuid whose canonical tmux session matches the requested session name.
    :ets.foldl(
      fn {id, stored_session}, acc ->
        if acc == nil and stored_session == tmux_session, do: id, else: acc
      end,
      nil,
      @aliases
    )
  end

  @doc "Handle a TeamCreate tool input map by emitting team_create_requested."
  @spec handle_team_create(map()) :: :ok
  def handle_team_create(input) do
    if team_name = input["team_name"] do
      Signals.emit(:team_create_requested, %{team_name: team_name})
    end

    :ok
  end

  @doc "Handle a TeamDelete tool input map by emitting team_delete_requested."
  @spec handle_team_delete(map()) :: :ok
  def handle_team_delete(input) do
    if team_name = input["team_name"] do
      Signals.emit(:team_delete_requested, %{team_name: team_name})
    end

    :ok
  end

  # Private helpers

  # Returns true if EventStream already has any event recorded for this session_id,
  # or if the session_id is registered as a canonical alias. This replaces the
  # former AgentProcess.alive?/1 check, keeping the query inside EventStream's own
  # ETS state instead of crossing into the Infrastructure domain.
  defp session_known?(session_id) do
    :ets.member(@aliases, session_id) or
      :ets.match(@table, {:_, %{session_id: session_id}}) != []
  end

  defp emit_session_started(session_id, event) do
    tmux_session = if event.tmux_session != "", do: event.tmux_session, else: nil

    Signals.emit(:session_started, %{
      session_id: session_id,
      tmux_session: tmux_session,
      cwd: event.cwd,
      model: event.model_name,
      os_pid: event.os_pid
    })
  end
end
