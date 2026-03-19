defmodule Ichor.Observability do
  @moduledoc """
  Ash Domain: Everything that happened.

  Events are durable facts. Activity provides runtime projections.
  All events flow through the Signals nervous system first.
  """
  use Ash.Domain, validate_config_inclusion?: false

  alias Ichor.Activity.Error
  alias Ichor.Activity.Message
  alias Ichor.Activity.Task, as: ActivityTask
  alias Ichor.Events.Event
  alias Ichor.Events.Session
  alias Ichor.Signals.Event, as: SignalEvent

  resources do
    resource(Event)
    resource(Session)
    resource(Message)
    resource(ActivityTask)
    resource(Error)
    resource(SignalEvent)
  end

  @spec list_events(keyword()) :: [Event.t()]
  def list_events(opts \\ []), do: Event.read!(opts)

  @spec list_recent_messages() :: list(Message.t())
  def list_recent_messages, do: Message.recent!()

  @spec list_current_tasks() :: list(ActivityTask.t())
  def list_current_tasks, do: ActivityTask.current!()

  @spec list_recent_errors() :: list(Error.t())
  def list_recent_errors, do: Error.recent!()

  @spec list_error_groups() :: list(map())
  def list_error_groups, do: Error.by_tool!()
end
