defmodule Ichor.Signals.Runtime do
  @moduledoc """
  Host implementation of the Ichor.Signals contract.
  Owns transport, envelope building, catalog validation, and PubSub broadcast.
  Configured as the signals_impl in config.exs.
  """

  @behaviour Ichor.Signals.Behaviour

  alias Ichor.Signals.{Bus, Catalog, Message, Topics}

  @impl true
  @spec emit(atom(), map()) :: :ok
  def emit(name, data \\ %{}) when is_atom(name) do
    info = Catalog.lookup!(name)
    message = Message.build(name, info.category, data)
    broadcast_static(info, message)
  end

  @impl true
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

  @impl true
  @spec subscribe(atom()) :: :ok | {:error, term()}
  def subscribe(name) when is_atom(name) do
    case Catalog.valid_category?(name) do
      true -> Bus.subscribe(Topics.category(name))
      false -> Bus.subscribe(Topics.signal(Catalog.lookup!(name).category, name))
    end
  end

  @impl true
  @spec subscribe(atom(), String.t()) :: :ok | {:error, term()}
  def subscribe(name, scope_id) when is_atom(name) and is_binary(scope_id) do
    info = Catalog.lookup!(name)
    true = info.dynamic
    Bus.subscribe(Topics.scoped(info.category, name, scope_id))
  end

  @impl true
  @spec unsubscribe(atom()) :: :ok
  def unsubscribe(name) when is_atom(name) do
    case {Catalog.valid_category?(name), Catalog.lookup(name)} do
      {true, _} -> Bus.unsubscribe(Topics.category(name))
      {_, %{category: cat}} -> Bus.unsubscribe(Topics.signal(cat, name))
      _ -> :ok
    end
  end

  @impl true
  def unsubscribe(name, scope_id) when is_atom(name) and is_binary(scope_id) do
    case Catalog.lookup(name) do
      %{dynamic: true} = info ->
        Bus.unsubscribe(Topics.scoped(info.category, name, scope_id))

      _ ->
        :ok
    end
  end

  @impl true
  @spec category_topic(atom()) :: String.t()
  def category_topic(category), do: Topics.category(category)

  @impl true
  @spec categories() :: [atom()]
  def categories, do: Catalog.categories()

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
