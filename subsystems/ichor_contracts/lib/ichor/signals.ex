defmodule Ichor.Signals do
  @moduledoc """
  Contract facade for the ICHOR signal API.
  """

  @behaviour Ichor.Signals.Behaviour

  @impl true
  @spec emit(atom(), map()) :: :ok
  def emit(name, data \\ %{}) when is_atom(name) do
    impl().emit(name, data)
  end

  @impl true
  @spec emit(atom(), String.t(), map()) :: :ok
  def emit(name, scope_id, data) when is_atom(name) and is_binary(scope_id) do
    impl().emit(name, scope_id, data)
  end

  @impl true
  @spec subscribe(atom()) :: :ok | {:error, term()}
  def subscribe(name) when is_atom(name) do
    impl().subscribe(name)
  end

  @impl true
  @spec subscribe(atom(), String.t()) :: :ok | {:error, term()}
  def subscribe(name, scope_id) when is_atom(name) and is_binary(scope_id) do
    impl().subscribe(name, scope_id)
  end

  @impl true
  @spec unsubscribe(atom()) :: :ok
  def unsubscribe(name) when is_atom(name) do
    impl().unsubscribe(name)
  end

  @impl true
  @spec unsubscribe(atom(), String.t()) :: :ok
  def unsubscribe(name, scope_id) when is_atom(name) and is_binary(scope_id) do
    impl().unsubscribe(name, scope_id)
  end

  @impl true
  @spec category_topic(atom()) :: String.t()
  def category_topic(category), do: impl().category_topic(category)

  @impl true
  @spec categories() :: [atom()]
  def categories, do: impl().categories()

  defp impl do
    Application.get_env(:ichor_contracts, :signals_impl, Ichor.Signals.Noop)
  end
end
