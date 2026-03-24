defmodule Ichor.Events do
  @moduledoc """
  Event bus. Accepts domain events and pushes them into the GenStage pipeline.
  """

  alias Ichor.Events.Event

  @spec emit(Event.t()) :: :ok
  def emit(%Event{} = event) do
    Ichor.Events.Ingress.push(event)
    :ok
  end
end
