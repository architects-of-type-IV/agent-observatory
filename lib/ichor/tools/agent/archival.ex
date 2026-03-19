defmodule Ichor.Tools.Agent.Archival do
  @moduledoc """
  Archival memory tools for agents. Long-term passage storage and search.
  """
  use Ash.Resource, domain: Ichor.Tools

  alias Ichor.MemoryStore

  actions do
    action :archival_memory_insert, :map do
      description(
        "Store information in your long-term archival memory. Tag entries for easier retrieval."
      )

      argument(:agent_name, :string, allow_nil?: false)
      argument(:content, :string, allow_nil?: false)
      argument(:tags, {:array, :string}, allow_nil?: true)

      run(fn input, _context ->
        args = input.arguments
        tags = args[:tags] || []

        case MemoryStore.archival_memory_insert(args.agent_name, args.content, tags) do
          {:ok, passage} ->
            {:ok, %{"status" => "stored", "id" => passage.id, "tags" => passage.tags}}

          {:error, reason} ->
            {:error, "Failed to store: #{inspect(reason)}"}
        end
      end)
    end

    action :archival_memory_search, {:array, :map} do
      description("Search your long-term archival memory by keyword. Optionally filter by tags.")

      argument(:agent_name, :string, allow_nil?: false)
      argument(:query, :string, allow_nil?: false)
      argument(:tags, {:array, :string}, allow_nil?: true)
      argument(:page, :integer, allow_nil?: true)

      run(fn input, _context ->
        args = input.arguments
        tags = args[:tags] || []
        page = args[:page] || 0

        case MemoryStore.archival_memory_search(args.agent_name, args.query,
               tags: tags,
               page: page
             ) do
          {:ok, results} ->
            {:ok,
             Enum.map(results, fn e ->
               %{
                 "id" => e.id,
                 "content" => e.content,
                 "tags" => e.tags || [],
                 "timestamp" => e.timestamp
               }
             end)}

          {:error, reason} ->
            {:error, "Search failed: #{inspect(reason)}"}
        end
      end)
    end
  end
end
