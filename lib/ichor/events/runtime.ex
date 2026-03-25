defmodule Ichor.Events.Runtime do
  @moduledoc """
  PubSub observation layer for ICHOR events.

  Handles subscribe/unsubscribe for PubSub observers (dashboard, projectors)
  and the temporary `broadcast_event/1` bridge that converts Events to Messages
  for backward-compatible PubSub consumers.

  Not part of the core event path. Core path: `Events.emit` -> `Ingress.push`.
  """

  alias Ichor.Events.{Event, Message, Registry, Topics}

  # ── Subscribe / Unsubscribe ───────────────────────────────────────

  @spec subscribe(atom()) :: :ok | {:error, term()}
  def subscribe(name) when is_atom(name) do
    if Registry.valid_category?(name) do
      pubsub_subscribe(Topics.category(name))
    else
      pubsub_subscribe(Topics.signal(Registry.category_for(name), name))
    end
  end

  @spec subscribe(atom(), String.t()) :: :ok | {:error, term()}
  def subscribe(name, scope_id) when is_atom(name) and is_binary(scope_id) do
    category = Registry.category_for(name)
    pubsub_subscribe(Topics.scoped(category, name, scope_id))
  end

  @spec unsubscribe(atom()) :: :ok
  def unsubscribe(name) when is_atom(name) do
    if Registry.valid_category?(name) do
      pubsub_unsubscribe(Topics.category(name))
    else
      category = Registry.category_for(name)
      pubsub_unsubscribe(Topics.signal(category, name))
    end
  end

  @spec unsubscribe(atom(), String.t()) :: :ok
  def unsubscribe(name, scope_id) when is_atom(name) and is_binary(scope_id) do
    if Registry.dynamic?(name) do
      category = Registry.category_for(name)
      pubsub_unsubscribe(Topics.scoped(category, name, scope_id))
    else
      :ok
    end
  end

  @spec category_topic(atom()) :: String.t()
  def category_topic(category), do: Topics.category(category)

  @spec categories() :: [atom()]
  def categories, do: Registry.categories()

  # ── Observer bridge (temporary) ───────────────────────────────────

  @doc """
  Bridge an %Event{} to PubSub for observer backward compat.

  Reads `legacy_name` from event metadata to produce a Message on the
  correct PubSub category topic. No-op if `legacy_name` is absent.

  Temporary -- remove when all PubSub subscribers migrate to pipeline.
  """
  @spec broadcast_event(Event.t()) :: :ok
  def broadcast_event(%Event{metadata: %{legacy_name: name}} = event) when is_atom(name) do
    category = Registry.category_for(name)
    message = Message.build(name, category, event.data)
    pubsub_broadcast(Topics.category(category), message)
    pubsub_broadcast(Topics.signal(category, name), message)
    :telemetry.execute([:ichor, :signal, name], %{count: 1}, %{signal: message})
    :ok
  end

  def broadcast_event(%Event{}), do: :ok

  # ── PubSub helpers ────────────────────────────────────────────────

  @pubsub Ichor.PubSub

  defp pubsub_subscribe(topic), do: Phoenix.PubSub.subscribe(@pubsub, topic)

  defp pubsub_unsubscribe(topic), do: Phoenix.PubSub.unsubscribe(@pubsub, topic)

  defp pubsub_broadcast(topic, %Message{} = message) do
    Phoenix.PubSub.broadcast(@pubsub, topic, message)
  end
end
