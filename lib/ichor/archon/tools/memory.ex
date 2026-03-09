defmodule Ichor.Archon.Tools.Memory do
  @moduledoc """
  Knowledge graph memory tools for Archon.

  Search and store observations in the Memories knowledge graph.
  Uses the Archon-dedicated namespace for all operations.
  """
  use Ash.Resource, domain: Ichor.Archon.Tools

  alias Ichor.Archon.MemoriesClient

  actions do
    action :search_memory, :map do
      description "Search Archon's knowledge graph for facts, entities, or episodes matching a query. Use this to recall information from past observations and conversations."

      argument :query, :string, allow_nil?: false, description: "Natural language search query"
      argument :scope, :string, default: "edges", description: "Search scope: edges (facts), nodes (entities), or episodes"
      argument :limit, :integer, default: 5, description: "Maximum results to return"
      argument :space, :string, description: "Space namespace filter (e.g. project:ichor)"

      run fn input, _context ->
        args = input.arguments
        opts = [scope: args.scope, limit: args.limit]
        opts = if Map.get(args, :space), do: Keyword.put(opts, :space, args.space), else: opts
        MemoriesClient.search(args.query, opts)
      end
    end

    action :remember, :map do
      description "Store an observation in Archon's knowledge graph. The system will automatically extract entities and facts from the content. Use this to remember important information about agents, projects, decisions, or events."

      argument :content, :string, allow_nil?: false, description: "The observation to remember"
      argument :type, :string, default: "text", description: "Structural type: text (narrative), message (conversation), json (structured)"
      argument :space, :string, description: "Space namespace (e.g. project:ichor:archon)"

      run fn input, _context ->
        args = input.arguments
        opts = [type: args.type]
        opts = if Map.get(args, :space), do: Keyword.put(opts, :space, args.space), else: opts
        MemoriesClient.ingest(args.content, opts)
      end
    end

    action :query_memory, :map do
      description "Ask a question about Archon's knowledge graph. Returns an LLM-generated answer grounded in retrieved evidence with full provenance."

      argument :query, :string, allow_nil?: false, description: "Question to answer from memory"

      run fn input, _context ->
        MemoriesClient.query_memory(input.arguments.query)
      end
    end
  end
end
