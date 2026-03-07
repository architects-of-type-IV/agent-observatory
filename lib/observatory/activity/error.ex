defmodule Observatory.Activity.Error do
  @moduledoc """
  A tool error derived from PostToolUseFailure hook events.
  Uses Ash.DataLayer.Simple -- data is loaded by preparations, not persisted.
  """

  use Ash.Resource, domain: Observatory.Activity

  attributes do
    attribute :id, :string, primary_key?: true, allow_nil?: false, public?: true
    attribute :tool_name, :string, public?: true
    attribute :session_id, :string, public?: true
    attribute :source_app, :string, public?: true
    attribute :error, :string, public?: true
    attribute :timestamp, :utc_datetime_usec, public?: true
    attribute :tool_use_id, :string, public?: true
    attribute :cwd, :string, public?: true
    attribute :hook_event_type, :atom, public?: true
  end

  actions do
    read :recent do
      prepare {Observatory.Activity.Preparations.LoadErrors, []}
    end

    action :by_tool, {:array, :map} do
      run fn _input, _context ->
        errors = Observatory.Activity.Error.recent!()

        grouped =
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

        {:ok, grouped}
      end
    end
  end

  code_interface do
    define :recent
    define :by_tool
  end
end
