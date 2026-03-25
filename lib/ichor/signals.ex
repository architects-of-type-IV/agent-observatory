defmodule Ichor.Signals do
  @moduledoc """
  Ash domain and runtime facade for the ICHOR signal system.

  Exposes signal resources and their Ash actions as the canonical domain boundary,
  and delegates runtime emit/subscribe/unsubscribe operations to Runtime.
  """

  use Ash.Domain, extensions: [AshAi]

  alias Ichor.Signals.Runtime

  resources do
    resource(Ichor.Signals.Operations)
    resource(Ichor.Signals.HITLInterventionEvent)
    resource(Ichor.Signals.Checkpoint)
  end

  tools do
    tool(:check_operator_inbox, Ichor.Signals.Operations, :check_operator_inbox)
    tool(:check_inbox, Ichor.Signals.Operations, :check_inbox)
    tool(:acknowledge_message, Ichor.Signals.Operations, :acknowledge_message)
    tool(:send_message, Ichor.Signals.Operations, :agent_send_message)
    tool(:recent_messages, Ichor.Signals.Operations, :recent_messages)
    tool(:archon_send_message, Ichor.Signals.Operations, :operator_send_message)
    tool(:agent_events, Ichor.Signals.Operations, :agent_events)
  end

  @spec emit(atom()) :: :ok
  @spec emit(atom(), map()) :: :ok
  def emit(name, data \\ %{}) when is_atom(name) do
    Runtime.emit(name, data || %{})
  end

  @spec emit(atom(), String.t(), map()) :: :ok
  def emit(name, scope_id, data) when is_atom(name) and is_binary(scope_id) do
    Runtime.emit(name, scope_id, data)
  end

  @spec subscribe(atom()) :: :ok | {:error, term()}
  def subscribe(name) when is_atom(name), do: Runtime.subscribe(name)

  @spec subscribe(atom(), String.t()) :: :ok | {:error, term()}
  def subscribe(name, scope_id) when is_atom(name) and is_binary(scope_id),
    do: Runtime.subscribe(name, scope_id)

  @spec unsubscribe(atom()) :: :ok
  def unsubscribe(name) when is_atom(name), do: Runtime.unsubscribe(name)

  @spec unsubscribe(atom(), String.t()) :: :ok
  def unsubscribe(name, scope_id) when is_atom(name) and is_binary(scope_id),
    do: Runtime.unsubscribe(name, scope_id)

  @spec category_topic(atom()) :: String.t()
  def category_topic(category), do: Runtime.category_topic(category)

  @spec categories() :: [atom()]
  def categories, do: Runtime.categories()
end
