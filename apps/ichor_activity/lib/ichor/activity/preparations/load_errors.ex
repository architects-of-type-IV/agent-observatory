defmodule Ichor.Activity.Preparations.LoadErrors do
  @moduledoc """
  Loads errors from PostToolUseFailure hook events in the EventBuffer.
  """

  use Ash.Resource.Preparation

  alias Ash.DataLayer.Simple

  @impl true
  def prepare(query, _opts, _context) do
    errors =
      list_events()
      |> Enum.filter(&(&1.hook_event_type == :PostToolUseFailure))
      |> Enum.map(fn e ->
        struct!(Ichor.Activity.Error, %{
          id: e.id,
          tool_name: e.tool_name,
          session_id: e.session_id,
          source_app: e.source_app,
          error: (e.payload || %{})["error"] || "Unknown error",
          timestamp: e.inserted_at,
          tool_use_id: e.tool_use_id,
          cwd: e.cwd,
          hook_event_type: e.hook_event_type
        })
      end)

    Simple.set_data(query, errors)
  end

  defp list_events do
    event_buffer_module =
      Application.get_env(
        :ichor_activity,
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
