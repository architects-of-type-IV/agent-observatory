defmodule Ichor.Events do
  @moduledoc """
  Ash domain and public API for the ICHOR event system.

  Core path: `Events.emit(Event.new(...))` -> Ingress -> Router -> SignalProcess -> Handler

  PubSub broadcast is an observer side-channel for dashboard/logging, not part of the core flow.
  During migration, `legacy_name` metadata bridges events to the old PubSub system.
  """

  use Ash.Domain

  alias Ichor.Events.{Event, Ingress, Runtime}

  resources do
    resource(Ichor.Events.StoredEvent)
  end

  @doc """
  Emit a domain event into the pipeline.

  This is the primary event API. All domain facts flow through here.

      Events.emit(Event.new("fleet.agent.started", session_id, %{name: "worker-1"}, %{legacy_name: :agent_started}))

  During migration, include `legacy_name: :atom` in metadata to bridge
  to the old PubSub system for dashboard observation.
  """
  @spec emit(Event.t()) :: :ok
  def emit(%Event{} = event) do
    Ingress.push(event)
    Runtime.broadcast_event(event)
    :ok
  end
end
