defmodule Ichor.Signals.Noop do
  @moduledoc false

  alias Ichor.Signals.Topics

  @behaviour Ichor.Signals.Behaviour

  @impl true
  def emit(_name, _data), do: :ok

  @impl true
  def emit(_name, _scope_id, _data), do: :ok

  @impl true
  def subscribe(_name), do: :ok

  @impl true
  def subscribe(_name, _scope_id), do: :ok

  @impl true
  def unsubscribe(_name), do: :ok

  @impl true
  def unsubscribe(_name, _scope_id), do: :ok

  @impl true
  def category_topic(category), do: Topics.category(category)

  @impl true
  def categories, do: []
end
