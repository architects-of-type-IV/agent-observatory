defmodule Ichor.Signals.Preparations.LoadToolFailures do
  @moduledoc """
  Loads errors from PostToolUseFailure hook events in the EventBuffer.
  """

  use Ash.Resource.Preparation

  alias Ash.DataLayer.Simple
  alias Ichor.Signals.Preparations.EventBufferReader

  @impl true
  def prepare(query, _opts, _context) do
    errors =
      for e <- EventBufferReader.list_events(),
          e.hook_event_type == :PostToolUseFailure do
        struct!(Ichor.Signals.ToolFailure, %{
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
      end

    Simple.set_data(query, errors)
  end
end
