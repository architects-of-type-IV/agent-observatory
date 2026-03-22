defmodule Ichor.Signals.ToolFailure do
  @moduledoc """
  A tool error derived from PostToolUseFailure hook events.
  Uses Ash.DataLayer.Simple -- data is loaded by preparations, not persisted.
  """

  use Ash.Resource, domain: Ichor.Signals

  alias Ichor.Signals.Preparations.LoadToolFailures

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
        # Direct Ash.read -- avoid __MODULE__.recent() self-call which re-enters the
        # authorization stack recursively (ash-thinking Decision 6 rule 2).
        query = Ash.Query.for_read(__MODULE__, :recent)

        case Ash.read(query) do
          {:ok, errors} -> {:ok, group_by_tool(errors)}
          {:error, reason} -> {:error, reason}
        end
      end)
    end
  end

  code_interface do
    define(:recent)
    define(:by_tool)
  end

  defp group_by_tool(errors) do
    errors
    |> Enum.group_by(& &1.tool_name)
    |> Enum.map(fn {tool, errs} ->
      %{
        tool: tool,
        count: length(errs),
        latest: errs |> Enum.sort_by(& &1.timestamp, {:desc, DateTime}) |> List.first(),
        errors: errs
      }
    end)
    |> Enum.sort_by(& &1.count, :desc)
  end
end
