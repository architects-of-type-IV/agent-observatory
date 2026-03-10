defmodule Ichor.Signals.Bus do
  @moduledoc """
  Sole PubSub transport interface.

  Only this module talks directly to Phoenix.PubSub.
  Instrumentation, tracing, and logging hooks belong here.
  """

  alias Phoenix.PubSub

  @pubsub Ichor.PubSub

  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(topic), do: PubSub.subscribe(@pubsub, topic)

  @spec unsubscribe(String.t()) :: :ok
  def unsubscribe(topic), do: PubSub.unsubscribe(@pubsub, topic)

  @spec broadcast(String.t(), Ichor.Signals.Message.t()) :: :ok | {:error, term()}
  def broadcast(topic, %Ichor.Signals.Message{} = message) do
    PubSub.broadcast(@pubsub, topic, message)
  end
end
