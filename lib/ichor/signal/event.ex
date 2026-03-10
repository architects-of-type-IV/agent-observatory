defmodule Ichor.Signal.Event do
  @moduledoc """
  Ash Resource exposing signal operations as actions.
  Queryable by Archon and MCP tools.
  """
  use Ash.Resource, domain: Ichor.Signal

  alias Ichor.Signal.{Buffer, Catalog}

  actions do
    action :emit, :map do
      description("Emit a signal into the ICHOR nervous system.")

      argument :name, :atom do
        allow_nil?(false)
        description("Signal name from the catalog (e.g. :heartbeat, :agent_started)")
      end

      argument :data, :map do
        default(%{})
        description("Signal payload data")
      end

      run(fn input, _context ->
        Ichor.Signal.emit(input.arguments.name, input.arguments.data)
        {:ok, %{status: "emitted", name: input.arguments.name}}
      end)
    end

    action :emit_scoped, :map do
      description("Emit a dynamic signal scoped to a specific agent/team/session.")

      argument :name, :atom do
        allow_nil?(false)
        description("Dynamic signal name (e.g. :agent_event, :dag_delta)")
      end

      argument :scope_id, :string do
        allow_nil?(false)
        description("Scope identifier (session_id, team_name, etc.)")
      end

      argument :data, :map do
        default(%{})
        description("Signal payload data")
      end

      run(fn input, _context ->
        args = input.arguments
        Ichor.Signal.emit(args.name, args.scope_id, args.data)
        {:ok, %{status: "emitted", name: args.name, scope_id: args.scope_id}}
      end)
    end

    action :recent, {:array, :map} do
      description("Get recent signals from the live feed buffer.")

      argument :limit, :integer do
        default(100)
        description("Max number of recent signals to return")
      end

      run(fn input, _context ->
        {:ok, Buffer.recent(input.arguments.limit)}
      end)
    end

    action :catalog, {:array, :map} do
      description("List all signal definitions in the ICHOR nervous system.")

      argument :category, :atom do
        description("Filter by category (e.g. :fleet, :agent, :system). Omit for all.")
      end

      run(fn input, _context ->
        signals =
          case input.arguments[:category] do
            nil -> Catalog.all() |> Enum.to_list()
            cat -> Catalog.by_category(cat)
          end

        result =
          Enum.map(signals, fn {name, info} ->
            %{
              name: name,
              category: info.category,
              keys: info.keys,
              dynamic: info.dynamic,
              doc: info.doc
            }
          end)

        {:ok, result}
      end)
    end
  end
end
