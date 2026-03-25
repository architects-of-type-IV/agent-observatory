defmodule Ichor.Infrastructure.MemoriesOperations do
  @moduledoc """
  Ash resource wrapping the MemoriesClient HTTP API as generic actions.

  Provides a domain-level, policy-ready, code_interface-callable surface for
  all Memories knowledge graph operations. The underlying MemoriesClient is
  not modified.
  """

  use Ash.Resource, domain: Ichor.Infrastructure

  alias Ichor.Infrastructure.MemoriesClient

  code_interface do
    define(:search, args: [:query])
    define(:ingest, args: [:content])
    define(:query, args: [:query])
  end

  actions do
    action :search, {:array, :map} do
      description("Search the Memories knowledge graph for edges or episodes matching a query.")

      argument(:query, :string, allow_nil?: false)
      argument(:scope, :string, allow_nil?: false, default: "edges")
      argument(:limit, :integer, allow_nil?: false, default: 10)

      run(fn input, _context ->
        with {:ok, results} <-
               MemoriesClient.search(input.arguments.query,
                 scope: input.arguments.scope,
                 limit: input.arguments.limit
               ) do
          {:ok, Enum.map(results, &map_search_result/1)}
        end
      end)
    end

    action :ingest, :map do
      description("Ingest content into the Memories knowledge graph.")

      argument(:content, :string, allow_nil?: false)
      argument(:type, :string, allow_nil?: false, default: "text")
      argument(:source, :string, allow_nil?: false, default: "agent")
      argument(:space, :string, allow_nil?: true)
      argument(:extraction_instructions, :string, allow_nil?: true)

      run(fn input, _context ->
        opts =
          [
            type: input.arguments.type,
            source: input.arguments.source
          ]
          |> then(fn o ->
            if input.arguments.space, do: Keyword.put(o, :space, input.arguments.space), else: o
          end)
          |> then(fn o ->
            if input.arguments.extraction_instructions,
              do:
                Keyword.put(
                  o,
                  :extraction_instructions,
                  input.arguments.extraction_instructions
                ),
              else: o
          end)

        with {:ok, result} <- MemoriesClient.ingest(input.arguments.content, opts) do
          {:ok, map_ingest_result(result)}
        end
      end)
    end

    action :query, :map do
      description("Query the Memories knowledge graph with a natural language question.")

      argument(:query, :string, allow_nil?: false)
      argument(:limit, :integer, allow_nil?: false, default: 10)

      run(fn input, _context ->
        with {:ok, result} <-
               MemoriesClient.query_memory(input.arguments.query, limit: input.arguments.limit) do
          {:ok,
           %{
             "answer" => result.answer,
             "citations" => result.citations,
             "context" => result.context
           }}
        end
      end)
    end
  end

  defp map_search_result(r) do
    %{
      "uuid" => r.uuid,
      "fact" => r.fact,
      "name" => r.name,
      "source" => r.source,
      "target" => r.target,
      "score" => r.score,
      "created_at" => r.created_at
    }
  end

  defp map_ingest_result(%{chunked: true} = r) do
    %{
      "chunked" => true,
      "chunk_count" => r.chunk_count,
      "episodes" => Enum.map(r.episodes, &map_single_ingest/1)
    }
  end

  defp map_ingest_result(r), do: map_single_ingest(r)

  defp map_single_ingest(r) do
    %{
      "episode_id" => r.episode_id,
      "group_id" => r.group_id,
      "status" => r.status,
      "sync_status" => r.sync_status
    }
  end
end
