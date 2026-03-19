defmodule Ichor.Observability do
  @moduledoc """
  Ash Domain: Everything that happened.

  Events are durable facts. Activity provides runtime projections.
  All events flow through the Signals nervous system first.
  """
  use Ash.Domain

  alias Ichor.Activity.Error
  alias Ichor.Activity.Message
  alias Ichor.Activity.Task, as: ActivityTask
  alias Ichor.Events.Event
  alias Ichor.Events.Session
  alias Ichor.Gateway.HITLInterventionEvent
  alias Ichor.Signals.Event, as: SignalEvent

  resources do
    resource(Event)
    resource(Session)
    resource(Message)
    resource(ActivityTask)
    resource(Error)
    resource(SignalEvent)
    resource(HITLInterventionEvent)
  end

  @doc "Returns events, optionally filtered by opts passed to the read action."
  @spec list_events(keyword()) :: [Event.t()]
  def list_events(opts \\ []), do: Event.read!(opts)

  @doc "Returns the most recent messages across all agents."
  @spec list_recent_messages() :: list(Message.t())
  def list_recent_messages, do: Message.recent!()

  @doc "Returns tasks that are currently in progress."
  @spec list_current_tasks() :: list(ActivityTask.t())
  def list_current_tasks, do: ActivityTask.current!()

  @doc "Returns recent errors across all agents and tools."
  @spec list_recent_errors() :: list(Error.t())
  def list_recent_errors, do: Error.recent!()

  @doc "Returns errors grouped by tool name with occurrence counts."
  @spec list_error_groups() :: list(map())
  def list_error_groups, do: Error.by_tool!()

  @doc "Records a HITL operator intervention in the audit trail."
  @spec record_hitl_intervention(map()) ::
          {:ok, HITLInterventionEvent.t()} | {:error, Ash.Error.t()}
  def record_hitl_intervention(attrs), do: HITLInterventionEvent.record(attrs)

  @doc "Returns HITL intervention events for a given session."
  @spec list_hitl_interventions_by_session(String.t()) :: list(HITLInterventionEvent.t())
  def list_hitl_interventions_by_session(session_id),
    do: HITLInterventionEvent.by_session!(session_id)

  @doc "Returns recent HITL intervention events across all operators."
  @spec list_recent_hitl_interventions() :: list(HITLInterventionEvent.t())
  def list_recent_hitl_interventions, do: HITLInterventionEvent.recent!()
end
