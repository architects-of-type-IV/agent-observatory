defmodule Ichor.Signals.DefaultHandler do
  @moduledoc """
  Default signal handler. Logs the activation.
  """

  require Logger

  alias Ichor.Signals.Signal

  @spec handle(Signal.t()) :: :ok
  def handle(%Signal{} = signal) do
    Logger.info(
      "[Signal] #{signal.name} activated for key=#{inspect(signal.key)} " <>
        "events=#{length(signal.events)}"
    )

    :ok
  end
end
