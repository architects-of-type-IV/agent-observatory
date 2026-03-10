defmodule Ichor.Signals do
  @moduledoc """
  Ash Domain: the ICHOR nervous system.

  Centralized signal protocol layer. Owns transport, envelope, topic naming,
  and publish/subscribe API. Business domains own business meaning.

  ## Emit

      Ichor.Signals.emit(:agent_started, %{session_id: sid, role: "worker"})
      Ichor.Signals.emit(:agent_event, scope_id, %{event: event})

  ## Subscribe

      Ichor.Signals.subscribe(:fleet)
      Ichor.Signals.subscribe(:agent_started)
      Ichor.Signals.subscribe(:agent_event, session_id)

  ## Receive

      def handle_info(%Ichor.Signals.Message{name: :agent_started, data: data}, socket)
  """

  use Ash.Domain

  alias Ichor.Signals.{Bus, Catalog, Message, Topics}

  resources do
    resource(Ichor.Signals.Event)
  end

  # ── Emit ──────────────────────────────────────────────────────────────

  @spec emit(atom(), map()) :: :ok
  def emit(name, data \\ %{}) when is_atom(name) do
    info = Catalog.lookup!(name)
    message = Message.build(name, info.category, data)
    broadcast_static(info, message)
  end

  @spec emit(atom(), String.t(), map()) :: :ok
  def emit(name, scope_id, data) when is_atom(name) and is_binary(scope_id) do
    info = Catalog.lookup!(name)
    true = info.dynamic
    message = Message.build(name, info.category, Map.put(data, :scope_id, scope_id))

    Bus.broadcast(Topics.category(info.category), message)
    Bus.broadcast(Topics.scoped(info.category, name, scope_id), message)
    tap_telemetry(name, message)
    :ok
  end

  # ── Subscribe ─────────────────────────────────────────────────────────

  @spec subscribe(atom()) :: :ok | {:error, term()}
  def subscribe(name) when is_atom(name) do
    cond do
      Catalog.valid_category?(name) ->
        Bus.subscribe(Topics.category(name))

      Catalog.lookup(name) ->
        info = Catalog.lookup!(name)
        Bus.subscribe(Topics.signal(info.category, name))

      true ->
        raise ArgumentError, "unknown signal or category: #{inspect(name)}"
    end
  end

  @spec subscribe(atom(), String.t()) :: :ok | {:error, term()}
  def subscribe(name, scope_id) when is_atom(name) and is_binary(scope_id) do
    info = Catalog.lookup!(name)
    true = info.dynamic
    Bus.subscribe(Topics.scoped(info.category, name, scope_id))
  end

  # ── Unsubscribe ───────────────────────────────────────────────────────

  @spec unsubscribe(atom()) :: :ok
  def unsubscribe(name) when is_atom(name) do
    cond do
      Catalog.valid_category?(name) ->
        Bus.unsubscribe(Topics.category(name))

      Catalog.lookup(name) ->
        info = Catalog.lookup!(name)
        Bus.unsubscribe(Topics.signal(info.category, name))

      true ->
        :ok
    end
  end

  def unsubscribe(name, scope_id) when is_atom(name) and is_binary(scope_id) do
    case Catalog.lookup(name) do
      %{dynamic: true} = info ->
        Bus.unsubscribe(Topics.scoped(info.category, name, scope_id))

      _ ->
        :ok
    end
  end

  # ── Public helpers ────────────────────────────────────────────────────

  @doc false
  def category_topic(category), do: Topics.category(category)

  # ── Internal ──────────────────────────────────────────────────────────

  defp broadcast_static(info, message) do
    Bus.broadcast(Topics.category(info.category), message)
    Bus.broadcast(Topics.signal(info.category, message.name), message)
    tap_telemetry(message.name, message)
    :ok
  end

  defp tap_telemetry(name, message) do
    :telemetry.execute([:ichor, :signal, name], %{count: 1}, %{signal: message})
  end
end
