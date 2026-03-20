defmodule Ichor.Observability do
  @moduledoc """
  Ash Domain: Everything that happened.

  Events are durable facts. Activity provides runtime projections.
  All events flow through the Signals nervous system first.
  """
  use Ash.Domain

  alias Ichor.Gateway.HITLInterventionEvent
  alias Ichor.Observability.Error
  alias Ichor.Observability.Event
  alias Ichor.Observability.Message
  alias Ichor.Observability.Session
  alias Ichor.Observability.Task, as: ObservabilityTask
  alias Ichor.Signals.Event, as: SignalEvent

  resources do
    resource(Event)
    resource(Session)
    resource(Message)
    resource(ObservabilityTask)
    resource(Error)
    resource(SignalEvent)
    resource(HITLInterventionEvent)
  end
end
