defmodule Ichor.Signals do
  @moduledoc """
  Ash domain and runtime facade for the ICHOR signal system.

  Exposes signal resources and their Ash actions as the canonical domain boundary,
  and delegates runtime emit/subscribe/unsubscribe operations to a configurable impl.
  """

  use Ash.Domain, extensions: [AshAi]

  @behaviour Ichor.Signals.Behaviour

  resources do
    resource(Ichor.Signals.Event)
    resource(Ichor.Signals.Operations)
    resource(Ichor.Signals.HITLInterventionEvent)
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

  @impl true
  @spec emit(atom()) :: :ok
  @spec emit(atom(), map()) :: :ok
  def emit(name, data \\ %{}) when is_atom(name) do
    impl().emit(name, data || %{})
  end

  @impl true
  @spec emit(atom(), String.t(), map()) :: :ok
  def emit(name, scope_id, data) when is_atom(name) and is_binary(scope_id) do
    impl().emit(name, scope_id, data)
  end

  @impl true
  @spec subscribe(atom()) :: :ok | {:error, term()}
  def subscribe(name) when is_atom(name), do: impl().subscribe(name)

  @impl true
  @spec subscribe(atom(), String.t()) :: :ok | {:error, term()}
  def subscribe(name, scope_id) when is_atom(name) and is_binary(scope_id),
    do: impl().subscribe(name, scope_id)

  @impl true
  @spec unsubscribe(atom()) :: :ok
  def unsubscribe(name) when is_atom(name), do: impl().unsubscribe(name)

  @impl true
  @spec unsubscribe(atom(), String.t()) :: :ok
  def unsubscribe(name, scope_id) when is_atom(name) and is_binary(scope_id),
    do: impl().unsubscribe(name, scope_id)

  @impl true
  @spec category_topic(atom()) :: String.t()
  def category_topic(category), do: impl().category_topic(category)

  @impl true
  @spec categories() :: [atom()]
  def categories, do: impl().categories()

  defp impl do
    Application.get_env(:ichor, :signals_impl, Ichor.Signals.Noop)
  end
end
