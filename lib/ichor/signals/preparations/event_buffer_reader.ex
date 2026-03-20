defmodule Ichor.Signals.Preparations.EventBufferReader do
  @moduledoc false

  @spec list_events() :: list()
  def list_events do
    event_buffer_module =
      Application.get_env(
        :ichor,
        :event_buffer_module,
        Module.concat([Ichor, EventBuffer])
      )

    if Code.ensure_loaded?(event_buffer_module) and
         function_exported?(event_buffer_module, :list_events, 0) do
      event_buffer_module.list_events()
    else
      []
    end
  end
end
