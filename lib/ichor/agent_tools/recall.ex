defmodule Ichor.AgentTools.Recall do
  @moduledoc """
  Recall memory tools for agents. Search conversation history.
  """
  use Ash.Resource, domain: Ichor.AgentTools

  alias Ichor.MemoryStore

  actions do
    action :conversation_search, {:array, :map} do
      description "Search your conversation history by text. Returns matching messages from past interactions."

      argument :agent_name, :string, allow_nil?: false
      argument :query, :string, allow_nil?: false
      argument :page, :integer, allow_nil?: true

      run fn input, _context ->
        args = input.arguments
        page = args[:page] || 0

        case MemoryStore.conversation_search(args.agent_name, args.query, page: page) do
          {:ok, results} ->
            {:ok, Enum.map(results, fn e ->
              %{"id" => e.id, "role" => e.role, "content" => e.content, "timestamp" => e.timestamp}
            end)}

          {:error, reason} ->
            {:error, "Search failed: #{inspect(reason)}"}
        end
      end
    end

    action :conversation_search_date, {:array, :map} do
      description "Search your conversation history by date range."

      argument :agent_name, :string, allow_nil?: false
      argument :start_date, :string, allow_nil?: false
      argument :end_date, :string, allow_nil?: false

      run fn input, _context ->
        args = input.arguments

        case MemoryStore.conversation_search_date(args.agent_name, args.start_date, args.end_date) do
          {:ok, results} ->
            {:ok, Enum.map(results, fn e ->
              %{"id" => e.id, "role" => e.role, "content" => e.content, "timestamp" => e.timestamp}
            end)}

          {:error, reason} ->
            {:error, "Search failed: #{inspect(reason)}"}
        end
      end
    end
  end
end
