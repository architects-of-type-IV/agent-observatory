defmodule Ichor.Signal do
  @moduledoc """
  Ash Domain: the ICHOR nervous system.

  Every signal flows through this domain. Provides a typed, validated API
  over PubSub with telemetry tap on every emission.

  ## Emit

      Ichor.Signal.emit(:agent_started, %{session_id: sid, role: "worker"})
      Ichor.Signal.emit(:agent_event, scope_id, %{event: event})

  ## Subscribe

      Ichor.Signal.subscribe(:fleet)
      Ichor.Signal.subscribe(:agent_started)
      Ichor.Signal.subscribe(:agent_event, session_id)

  ## Receive

      def handle_info(%Ichor.Signal.Payload{name: :agent_started, data: data}, socket)
  """

  use Ash.Domain

  alias Ichor.Signal.{Catalog, Payload}

  resources do
    resource(Ichor.Signal.Event)
  end

  @pubsub Ichor.PubSub

  # ── Emit ──────────────────────────────────────────────────────────────

  @spec emit(atom(), map()) :: :ok
  def emit(name, data \\ %{}) when is_atom(name) do
    info = Catalog.lookup!(name)
    signal = Payload.build(name, info.category, data)
    broadcast_static(info, signal)
  end

  @spec emit(atom(), String.t(), map()) :: :ok
  def emit(name, scope_id, data) when is_atom(name) and is_binary(scope_id) do
    info = Catalog.lookup!(name)
    true = info.dynamic
    signal = Payload.build(name, info.category, Map.put(data, :scope_id, scope_id))

    Phoenix.PubSub.broadcast(@pubsub, category_topic(info.category), signal)
    Phoenix.PubSub.broadcast(@pubsub, scoped_topic(info.category, name, scope_id), signal)
    tap_telemetry(name, signal)
    :ok
  end

  # ── Subscribe ─────────────────────────────────────────────────────────

  @spec subscribe(atom()) :: :ok | {:error, term()}
  def subscribe(name) when is_atom(name) do
    cond do
      Catalog.valid_category?(name) ->
        Phoenix.PubSub.subscribe(@pubsub, category_topic(name))

      Catalog.lookup(name) ->
        info = Catalog.lookup!(name)
        Phoenix.PubSub.subscribe(@pubsub, signal_topic(info.category, name))

      true ->
        raise ArgumentError, "unknown signal or category: #{inspect(name)}"
    end
  end

  @spec subscribe(atom(), String.t()) :: :ok | {:error, term()}
  def subscribe(name, scope_id) when is_atom(name) and is_binary(scope_id) do
    info = Catalog.lookup!(name)
    true = info.dynamic
    Phoenix.PubSub.subscribe(@pubsub, scoped_topic(info.category, name, scope_id))
  end

  # ── Unsubscribe ───────────────────────────────────────────────────────

  @spec unsubscribe(atom()) :: :ok
  def unsubscribe(name) when is_atom(name) do
    cond do
      Catalog.valid_category?(name) ->
        Phoenix.PubSub.unsubscribe(@pubsub, category_topic(name))

      Catalog.lookup(name) ->
        info = Catalog.lookup!(name)
        Phoenix.PubSub.unsubscribe(@pubsub, signal_topic(info.category, name))

      true ->
        :ok
    end
  end

  def unsubscribe(name, scope_id) when is_atom(name) and is_binary(scope_id) do
    case Catalog.lookup(name) do
      %{dynamic: true} = info ->
        Phoenix.PubSub.unsubscribe(@pubsub, scoped_topic(info.category, name, scope_id))

      _ ->
        :ok
    end
  end

  # ── Internal ──────────────────────────────────────────────────────────

  defp broadcast_static(info, signal) do
    Phoenix.PubSub.broadcast(@pubsub, category_topic(info.category), signal)
    Phoenix.PubSub.broadcast(@pubsub, signal_topic(info.category, signal.name), signal)
    tap_telemetry(signal.name, signal)
    :ok
  end

  defp tap_telemetry(name, signal) do
    :telemetry.execute([:ichor, :signal, name], %{count: 1}, %{signal: signal})
  end

  @doc false
  def category_topic(category), do: "signal:#{category}"
  defp signal_topic(category, name), do: "signal:#{category}:#{name}"
  defp scoped_topic(category, name, scope_id), do: "signal:#{category}:#{name}:#{scope_id}"
end
