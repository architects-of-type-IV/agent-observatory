defmodule Ichor.Archon.Tools.Memory do
  @moduledoc """
  Knowledge graph memory tools for Archon.

  Search and store observations in the Memories knowledge graph.
  Uses the Archon-dedicated namespace for all operations.
  """
  use Ash.Resource, domain: Ichor.Tools

  alias Ichor.Archon.MemoriesClient

  actions do
    action :search_memory, :map do
      description(
        "Search Archon's knowledge graph for facts, entities, or episodes matching a query. Use this to recall information from past observations and conversations."
      )

      argument(:query, :string, allow_nil?: false, description: "Natural language search query")

      argument(:scope, :string,
        allow_nil?: false,
        default: "edges",
        description: "Search scope: edges (facts), nodes (entities), or episodes"
      )

      argument(:limit, :integer,
        allow_nil?: false,
        default: 5,
        description: "Maximum results to return"
      )

      argument(:space, :string,
        allow_nil?: false,
        default: "general",
        description: "Space namespace filter (e.g. general, project:ichor)"
      )

      run(fn input, _context ->
        args = input.arguments
        MemoriesClient.search(args.query, scope: args.scope, limit: args.limit, space: args.space)
      end)
    end

    action :remember, :map do
      description(
        "Store an observation in Archon's knowledge graph. The system will automatically extract entities and facts from the content. Use this to remember important information about agents, projects, decisions, or events."
      )

      argument(:content, :string, allow_nil?: false, description: "The observation to remember")

      argument(:type, :string,
        allow_nil?: false,
        default: "text",
        description:
          "Structural type: text (narrative), message (conversation), json (structured)"
      )

      argument(:space, :string,
        allow_nil?: false,
        default: "general",
        description: "Space namespace (e.g. general, project:ichor:archon)"
      )

      run(fn input, _context ->
        args = input.arguments
        MemoriesClient.ingest(args.content, type: args.type, space: args.space)
      end)
    end

    action :query_memory, :map do
      description(
        "Ask a question about Archon's knowledge graph. Returns an LLM-generated answer grounded in retrieved evidence with full provenance."
      )

      argument(:query, :string, allow_nil?: false, description: "Question to answer from memory")

      run(fn input, _context ->
        MemoriesClient.query_memory(input.arguments.query)
      end)
    end
  end
end
