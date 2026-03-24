defmodule Ichor.Projector.SignalHandler do
  @moduledoc """
  Dispatches activated signals to their handlers.

  Handlers do the real work: Ash Reactor, Oban job, domain module,
  LLM adapter, aggregator. The projector stays dumb; this module
  routes the signal to whatever does the actual work.
  """

  alias Ichor.Projector.Signal

  require Logger

  @spec handle(Signal.t()) :: :ok
  def handle(%Signal{} = signal) do
    handler = resolve_handler(signal.name)

    case handler do
      nil ->
        Logger.debug("No handler registered for signal: #{signal.name}")
        :ok

      {mod, fun} ->
        try do
          apply(mod, fun, [signal])
        rescue
          e ->
            Logger.error(
              "Signal handler #{inspect(mod)}.#{fun}/1 crashed for #{signal.name}: #{Exception.message(e)}"
            )
        end

        :ok
    end
  end

  defp resolve_handler(signal_name) do
    handlers = Application.get_env(:ichor, :signal_handlers, %{})
    Map.get(handlers, signal_name)
  end
end
