defmodule Ichor.Events do
  @moduledoc """
  Ash domain and public API for the ICHOR event system.

  Core path: `Events.emit(Event.new(...))` -> Ingress -> Router -> SignalProcess -> Handler

  PubSub broadcast is an observer side-channel for dashboard/logging, not part of the core flow.
  During migration, `legacy_name` metadata bridges events to the old PubSub system.
  """

  use Ash.Domain

  alias Ichor.Events.{Event, Ingress}

  @pubsub Ichor.PubSub
  @all_topic "events:all"

  resources do
    resource(Ichor.Events.StoredEvent)
  end

  @doc """
  Emit a domain event into the pipeline.

  Core path: Ingress.push -> Router -> SignalProcess -> Handler.
  PubSub broadcast on "events:all" + "events:{key}" for observers.

      Events.emit(Event.new("fleet.agent.started", session_id, %{name: "worker-1"}))
  """
  @spec emit(Event.t()) :: :ok
  def emit(%Event{} = event) do
    Ingress.push(event)
    Phoenix.PubSub.broadcast(@pubsub, @all_topic, event)
    if event.key, do: Phoenix.PubSub.broadcast(@pubsub, "events:#{event.key}", event)
    :ok
  end

  @doc "Subscribe to all events."
  @spec subscribe_all() :: :ok | {:error, term()}
  def subscribe_all, do: Phoenix.PubSub.subscribe(@pubsub, @all_topic)

  @doc "Subscribe to events for a specific key (session_id, run_id, etc.)."
  @spec subscribe_key(term()) :: :ok | {:error, term()}
  def subscribe_key(key), do: Phoenix.PubSub.subscribe(@pubsub, "events:#{key}")

  @doc "Unsubscribe from events for a specific key."
  @spec unsubscribe_key(term()) :: :ok
  def unsubscribe_key(key), do: Phoenix.PubSub.unsubscribe(@pubsub, "events:#{key}")
end
