defmodule Ichor.Events.Runtime do
  @moduledoc """
  Event broadcast runtime.
  Owns transport, envelope building, category validation, and PubSub broadcast.
  """

  require Logger

  alias Ichor.Events.{Event, Ingress, Message, Registry, Topics}

  @spec emit(atom(), map()) :: :ok
  def emit(name, data \\ %{}) when is_atom(name) do
    category = Registry.category_for(name)
    message = Message.build(name, category, data)
    broadcast_static(category, message)
  end

  @spec emit(atom(), String.t(), map()) :: :ok
  def emit(name, scope_id, data) when is_atom(name) and is_binary(scope_id) do
    unless Registry.dynamic?(name) do
      raise ArgumentError, "Signal #{name} is not dynamic; cannot emit with scope_id"
    end

    category = Registry.category_for(name)
    message = Message.build(name, category, Map.put(data, :scope_id, scope_id))
    broadcast_scoped(category, name, scope_id, message)
  end

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

  defp broadcast_scoped(category, name, scope_id, message) do
    pubsub_broadcast(Topics.category(category), message)
    pubsub_broadcast(Topics.scoped(category, name, scope_id), message)
    tap_telemetry(name, message)
    bridge_to_pipeline(name, message.data)
    :ok
  end

  defp broadcast_static(category, message) do
    pubsub_broadcast(Topics.category(category), message)
    pubsub_broadcast(Topics.signal(category, message.name), message)
    tap_telemetry(message.name, message)
    bridge_to_pipeline(message.name, message.data)
    :ok
  end

  defp bridge_to_pipeline(name, data) do
    topic = "signal.#{name}"
    key = extract_key(data)
    event = Event.new(topic, key, data, %{source: :signal_bridge, legacy_name: name})
    Ingress.push(event)
  end

  @key_fields [:session_id, :run_id, :team_name, :project_id, :agent_id]

  defp extract_key(data) when is_map(data) do
    Enum.find_value(@key_fields, fn field ->
      Map.get(data, field) || Map.get(data, Atom.to_string(field))
    end)
  end

  defp tap_telemetry(name, message) do
    :telemetry.execute([:ichor, :signal, name], %{count: 1}, %{signal: message})
  end

  @pubsub Ichor.PubSub

  defp pubsub_subscribe(topic), do: Phoenix.PubSub.subscribe(@pubsub, topic)

  defp pubsub_unsubscribe(topic), do: Phoenix.PubSub.unsubscribe(@pubsub, topic)

  defp pubsub_broadcast(topic, %Message{} = message) do
    Phoenix.PubSub.broadcast(@pubsub, topic, message)
  end
end
