defmodule Ichor.Events.EventStream.AgentLifecycle do
  @moduledoc """
  Signal emission helper for hook-originated fleet lifecycle events.

  Translates raw hook event data into Signals-domain signals. Infrastructure
  subscribers react to those signals to perform the actual fleet mutations
  (spawn/terminate AgentProcess, create/disband TeamSupervisor).

  This module must NOT alias or import any Infrastructure module.
  """

  require Logger

  alias Ichor.Events
  alias Ichor.Events.Event

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
    e ->
      Logger.warning(
        "agent_lifecycle: resolve_or_create_agent failed for #{session_id}: #{inspect(e)}"
      )

      session_id
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

  @doc "Handle a team lifecycle tool input by emitting the corresponding signal."
  @spec handle_team_event(atom(), map()) :: :ok
  def handle_team_event(signal, input) do
    if team_name = input["team_name"] do
      emit_team_event(signal, team_name)
    end

    :ok
  end

  def handle_team_create(input), do: handle_team_event(:team_create_requested, input)
  def handle_team_delete(input), do: handle_team_event(:team_delete_requested, input)

  defp emit_team_event(:team_create_requested, team_name) do
    Events.emit(
      Event.new("fleet.team.create_requested", team_name, %{team_name: team_name}, %{
        legacy_name: :team_create_requested
      })
    )
  end

  defp emit_team_event(:team_delete_requested, team_name) do
    Events.emit(
      Event.new("fleet.team.delete_requested", team_name, %{team_name: team_name}, %{
        legacy_name: :team_delete_requested
      })
    )
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

  defp nil_if_empty(""), do: nil
  defp nil_if_empty(s), do: s

  defp emit_session_started(session_id, event) do
    tmux_session = nil_if_empty(event.tmux_session)

    data = %{
      session_id: session_id,
      tmux_session: tmux_session,
      cwd: event.cwd,
      model: event.model_name,
      os_pid: event.os_pid
    }

    Events.emit(
      Event.new("fleet.session.started", session_id, data, %{legacy_name: :session_started})
    )
  end
end
