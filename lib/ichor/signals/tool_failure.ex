defmodule Ichor.Signals.ToolFailure do
  @moduledoc """
  A tool error derived from PostToolUseFailure hook events.
  Uses Ash.DataLayer.Simple -- data is loaded by preparations, not persisted.
  """

  use Ash.Resource, domain: Ichor.SignalBus

  alias Ichor.Signals.Preparations.{EventBufferReader, LoadToolFailures}

  attributes do
    attribute(:id, :string, primary_key?: true, allow_nil?: false, public?: true)
    attribute(:tool_name, :string, public?: true)
    attribute(:session_id, :string, public?: true)
    attribute(:source_app, :string, public?: true)
    attribute(:error, :string, public?: true)
    attribute(:timestamp, :utc_datetime_usec, public?: true)
    attribute(:tool_use_id, :string, public?: true)
    attribute(:cwd, :string, public?: true)
    attribute(:hook_event_type, :atom, public?: true)
  end

  actions do
    read :recent do
      prepare({LoadToolFailures, []})
    end

    action :by_tool, {:array, :map} do
      run(fn _input, _context ->
        errors = load_recent_errors()
        {:ok, group_by_tool(errors)}
      end)
    end
  end

  code_interface do
    define(:recent)
    define(:by_tool)
  end

  defp load_recent_errors do
    EventBufferReader.list_events()
    |> Enum.filter(&(&1.hook_event_type == :PostToolUseFailure))
    |> Enum.map(fn e ->
      struct!(__MODULE__, %{
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
  end

  defp group_by_tool(errors) do
    errors
    |> Enum.group_by(& &1.tool_name)
    |> Enum.map(fn {tool, errs} ->
      %{
        tool: tool,
        count: length(errs),
        latest: List.first(Enum.sort_by(errs, & &1.timestamp, {:desc, DateTime})),
        errors: errs
      }
    end)
    |> Enum.sort_by(& &1.count, :desc)
  end
end
