defmodule Ichor.Activity.Preparations.LoadErrors do
  @moduledoc """
  Loads errors from PostToolUseFailure hook events in the EventBuffer.
  """

  use Ash.Resource.Preparation

  @impl true
  def prepare(query, _opts, _context) do
    errors =
      Ichor.EventBuffer.list_events()
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

    Ash.DataLayer.Simple.set_data(query, errors)
  end
end
