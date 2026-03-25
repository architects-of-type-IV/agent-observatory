defmodule Ichor.Signals.SignalHandler do
  @moduledoc """
  Default signal handler. Logs signal activations.

  The real downstream reactions happen in processes that subscribe to
  `"signal:{name}"` PubSub topics -- Archon, projectors, Oban workers.
  This handler is just observability.
  """

  require Logger

  alias Ichor.Signals.Signal

  @spec handle(Signal.t()) :: :ok
  def handle(%Signal{} = signal) do
    Logger.info(
      "[Signal] #{signal.name} key=#{inspect(signal.key)} metadata=#{inspect(signal.metadata)}"
    )

    :ok
  end
end
