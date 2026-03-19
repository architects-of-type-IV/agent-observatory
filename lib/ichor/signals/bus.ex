defmodule Ichor.Signals.Bus do
  @moduledoc """
  Sole PubSub transport interface.

  Only this module talks directly to Phoenix.PubSub.
  Instrumentation, tracing, and logging hooks belong here.
  """

  alias Phoenix.PubSub

  @pubsub Ichor.PubSub

  @doc "Subscribe the calling process to the given PubSub topic."
  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(topic), do: PubSub.subscribe(@pubsub, topic)

  @doc "Unsubscribe the calling process from the given PubSub topic."
  @spec unsubscribe(String.t()) :: :ok
  def unsubscribe(topic), do: PubSub.unsubscribe(@pubsub, topic)

  @doc "Broadcast a signal message to all subscribers of the given topic."
  @spec broadcast(String.t(), Ichor.Signals.Message.t()) :: :ok | {:error, term()}
  def broadcast(topic, %Ichor.Signals.Message{} = message) do
    PubSub.broadcast(@pubsub, topic, message)
  end
end
