defmodule Observatory.AgentTools.Memory do
  @moduledoc """
  Ash Resource exposing Letta-compatible memory tools via MCP.

  ## Tools (Letta V2)

  Core memory (in-context blocks):
  - `read_memory` -- load all blocks for context injection
  - `memory_replace` -- find-and-replace text in a block
  - `memory_insert` -- insert text at a line position in a block
  - `memory_rethink` -- rewrite a block entirely

  Recall memory (conversation history):
  - `conversation_search` -- search past messages by text
  - `conversation_search_date` -- search by date range

  Archival memory (long-term passages):
  - `archival_memory_insert` -- store a passage with tags
  - `archival_memory_search` -- keyword search passages

  Agent management:
  - `create_agent` -- register a new specialist agent with blocks
  - `list_agents` -- list all registered agents
  """
  use Ash.Resource, domain: Observatory.AgentTools

  alias Observatory.MemoryStore

  actions do
    # ═══════════════════════════════════════════════════════
    # Core Memory -- Read
    # ═══════════════════════════════════════════════════════

    action :read_memory, :map do
      description("""
      Read your core memory blocks. Returns all blocks pinned to your context \
      (persona, human, organization, etc.) plus recall/archival counts. \
      Call this first when starting a session to load your identity and context.\
      """)

      argument :agent_name, :string do
        allow_nil?(false)
        description("Your agent name (e.g. 'research-agent', 'code-agent')")
      end

      run(fn input, _context ->
        name = input.arguments.agent_name

        case MemoryStore.read_core_memory(name) do
          {:ok, memory} ->
            blocks =
              Enum.map(memory.blocks, fn b ->
                %{
                  "label" => b.label,
                  "description" => b.description,
                  "value" => b.value,
                  "read_only" => b.read_only
                }
              end)

            {:ok,
             %{
               "agent" => name,
               "blocks" => blocks,
               "recall_count" => memory.recall_count,
               "archival_count" => memory.archival_count
             }}

          {:error, :not_found} ->
            {:ok, %{"agent" => name, "blocks" => [], "recall_count" => 0, "archival_count" => 0}}
        end
      end)
    end

    # ═══════════════════════════════════════════════════════
    # Core Memory -- Edit (Letta V2 line-aware tools)
    # ═══════════════════════════════════════════════════════

    action :memory_replace, :map do
      description("""
      Replace text in a core memory block. Find `old_text` and replace \
      with `new_text`. Use this to update specific facts or details in \
      your memory without rewriting the entire block.\
      """)

      argument :agent_name, :string do
        allow_nil?(false)
        description("Your agent name")
      end

      argument :block_label, :string do
        allow_nil?(false)
        description("The block to edit (e.g. 'persona', 'human')")
      end

      argument :old_text, :string do
        allow_nil?(false)
        description("The exact text to find in the block")
      end

      argument :new_text, :string do
        allow_nil?(false)
        description("The replacement text")
      end

      run(fn input, _context ->
        args = input.arguments

        case MemoryStore.memory_replace(args.agent_name, args.block_label, args.old_text, args.new_text) do
          {:ok, block} ->
            {:ok, %{"status" => "replaced", "block" => args.block_label, "new_value" => block.value}}

          {:error, :text_not_found} ->
            {:error, "Text not found in block '#{args.block_label}'. Read the block first to see its current content."}

          {:error, :read_only} ->
            {:error, "Block '#{args.block_label}' is read-only and cannot be modified."}

          {:error, :exceeds_limit} ->
            {:error, "Replacement would exceed the block's character limit."}

          {:error, reason} ->
            {:error, "Failed: #{inspect(reason)}"}
        end
      end)
    end

    action :memory_insert, :map do
      description("""
      Insert text at a specific line position in a core memory block. \
      Line 0 inserts at the beginning. Use this to add new information \
      to a block without disturbing existing content.\
      """)

      argument :agent_name, :string do
        allow_nil?(false)
        description("Your agent name")
      end

      argument :block_label, :string do
        allow_nil?(false)
        description("The block to edit (e.g. 'persona', 'human')")
      end

      argument :position, :integer do
        allow_nil?(false)
        description("Line number to insert at (0-indexed)")
      end

      argument :text, :string do
        allow_nil?(false)
        description("The text to insert")
      end

      run(fn input, _context ->
        args = input.arguments

        case MemoryStore.memory_insert(args.agent_name, args.block_label, args.position, args.text) do
          {:ok, block} ->
            {:ok, %{"status" => "inserted", "block" => args.block_label, "new_value" => block.value}}

          {:error, :read_only} ->
            {:error, "Block '#{args.block_label}' is read-only."}

          {:error, :exceeds_limit} ->
            {:error, "Insert would exceed the block's character limit."}

          {:error, reason} ->
            {:error, "Failed: #{inspect(reason)}"}
        end
      end)
    end

    action :memory_rethink, :map do
      description("""
      Completely rewrite a core memory block with new content. Use this \
      when you need to restructure or substantially revise a block, not \
      just make small edits. The old content is fully replaced.\
      """)

      argument :agent_name, :string do
        allow_nil?(false)
        description("Your agent name")
      end

      argument :block_label, :string do
        allow_nil?(false)
        description("The block to rewrite (e.g. 'persona', 'human')")
      end

      argument :new_value, :string do
        allow_nil?(false)
        description("The complete new content for this block")
      end

      run(fn input, _context ->
        args = input.arguments

        case MemoryStore.memory_rethink(args.agent_name, args.block_label, args.new_value) do
          {:ok, block} ->
            {:ok, %{"status" => "rewritten", "block" => args.block_label, "new_value" => block.value}}

          {:error, :read_only} ->
            {:error, "Block '#{args.block_label}' is read-only."}

          {:error, :exceeds_limit} ->
            {:error, "New content exceeds the block's character limit."}

          {:error, reason} ->
            {:error, "Failed: #{inspect(reason)}"}
        end
      end)
    end

    # ═══════════════════════════════════════════════════════
    # Recall Memory (conversation history)
    # ═══════════════════════════════════════════════════════

    action :conversation_search, {:array, :map} do
      description("""
      Search your conversation history by text. Returns matching messages \
      from past interactions. Use this to recall what was discussed previously.\
      """)

      argument :agent_name, :string do
        allow_nil?(false)
        description("Your agent name")
      end

      argument :query, :string do
        allow_nil?(false)
        description("Text to search for in conversation history")
      end

      argument :page, :integer do
        allow_nil?(true)
        description("Page number for pagination (0-indexed, default 0)")
      end

      run(fn input, _context ->
        args = input.arguments
        page = args[:page] || 0

        case MemoryStore.conversation_search(args.agent_name, args.query, page: page) do
          {:ok, results} ->
            entries =
              Enum.map(results, fn e ->
                %{
                  "id" => e.id,
                  "role" => e.role,
                  "content" => e.content,
                  "timestamp" => e.timestamp
                }
              end)

            {:ok, entries}

          {:error, reason} ->
            {:error, "Search failed: #{inspect(reason)}"}
        end
      end)
    end

    action :conversation_search_date, {:array, :map} do
      description("""
      Search your conversation history by date range. Returns messages \
      between the start and end dates.\
      """)

      argument :agent_name, :string do
        allow_nil?(false)
        description("Your agent name")
      end

      argument :start_date, :string do
        allow_nil?(false)
        description("Start of date range (ISO 8601, e.g. '2026-02-20T00:00:00Z')")
      end

      argument :end_date, :string do
        allow_nil?(false)
        description("End of date range (ISO 8601, e.g. '2026-02-21T23:59:59Z')")
      end

      run(fn input, _context ->
        args = input.arguments

        case MemoryStore.conversation_search_date(args.agent_name, args.start_date, args.end_date) do
          {:ok, results} ->
            entries =
              Enum.map(results, fn e ->
                %{
                  "id" => e.id,
                  "role" => e.role,
                  "content" => e.content,
                  "timestamp" => e.timestamp
                }
              end)

            {:ok, entries}

          {:error, reason} ->
            {:error, "Search failed: #{inspect(reason)}"}
        end
      end)
    end

    # ═══════════════════════════════════════════════════════
    # Archival Memory (long-term passages)
    # ═══════════════════════════════════════════════════════

    action :archival_memory_insert, :map do
      description("""
      Store information in your long-term archival memory. Use this to \
      save facts, knowledge, decisions, or any information you want to \
      recall later. Tag entries for easier retrieval.\
      """)

      argument :agent_name, :string do
        allow_nil?(false)
        description("Your agent name")
      end

      argument :content, :string do
        allow_nil?(false)
        description("The information to store")
      end

      argument :tags, {:array, :string} do
        allow_nil?(true)
        description("Tags for categorization (e.g. ['fact', 'preference', 'decision'])")
      end

      run(fn input, _context ->
        args = input.arguments
        tags = args[:tags] || []

        case MemoryStore.archival_memory_insert(args.agent_name, args.content, tags) do
          {:ok, passage} ->
            {:ok,
             %{
               "status" => "stored",
               "id" => passage.id,
               "tags" => passage.tags
             }}

          {:error, reason} ->
            {:error, "Failed to store: #{inspect(reason)}"}
        end
      end)
    end

    action :archival_memory_search, {:array, :map} do
      description("""
      Search your long-term archival memory by keyword. Returns matching \
      passages. Optionally filter by tags. Use this to recall previously \
      stored knowledge.\
      """)

      argument :agent_name, :string do
        allow_nil?(false)
        description("Your agent name")
      end

      argument :query, :string do
        allow_nil?(false)
        description("Search query (keyword matching)")
      end

      argument :tags, {:array, :string} do
        allow_nil?(true)
        description("Filter by tags (returns entries matching ANY tag)")
      end

      argument :page, :integer do
        allow_nil?(true)
        description("Page number for pagination (0-indexed, default 0)")
      end

      run(fn input, _context ->
        args = input.arguments
        tags = args[:tags] || []
        page = args[:page] || 0

        case MemoryStore.archival_memory_search(args.agent_name, args.query, tags: tags, page: page) do
          {:ok, results} ->
            entries =
              Enum.map(results, fn e ->
                %{
                  "id" => e.id,
                  "content" => e.content,
                  "tags" => e.tags || [],
                  "timestamp" => e.timestamp
                }
              end)

            {:ok, entries}

          {:error, reason} ->
            {:error, "Search failed: #{inspect(reason)}"}
        end
      end)
    end

    # ═══════════════════════════════════════════════════════
    # Agent Management
    # ═══════════════════════════════════════════════════════

    action :create_agent, :map do
      description("""
      Register a new specialist agent with initial memory blocks. \
      Each block has a label (e.g. 'persona', 'human'), value (content), \
      and optional description and character limit.\
      """)

      argument :agent_name, :string do
        allow_nil?(false)
        description("Unique name for the agent (e.g. 'research-agent')")
      end

      argument :persona, :string do
        allow_nil?(false)
        description("The agent's persona block: who it is, how it behaves")
      end

      argument :human, :string do
        allow_nil?(true)
        description("The human block: information about the user this agent works with")
      end

      argument :extra_blocks, {:array, :map} do
        allow_nil?(true)
        description("Additional blocks: [{label, value, description?, limit?}]")
      end

      run(fn input, _context ->
        args = input.arguments

        blocks = [
          %{label: "persona", value: args.persona, description: "Your persona and behavioral guidelines."},
          %{label: "human", value: args[:human] || "", description: "Key details about the human you work with."}
        ]

        extra = Enum.map(args[:extra_blocks] || [], fn b ->
          %{
            label: b["label"] || b[:label],
            value: b["value"] || b[:value] || "",
            description: b["description"] || b[:description] || ""
          }
        end)

        case MemoryStore.create_agent(args.agent_name, blocks ++ extra) do
          {:ok, agent} ->
            {:ok,
             %{
               "status" => "created",
               "agent" => agent.name,
               "blocks" => length(agent.block_ids)
             }}

          {:error, :already_exists} ->
            {:error, "Agent '#{args.agent_name}' already exists."}
        end
      end)
    end

    action :list_agents, {:array, :map} do
      description("List all registered specialist agents with their memory block summaries.")

      run(fn _input, _context ->
        case MemoryStore.list_agents() do
          {:ok, agents} ->
            entries =
              Enum.map(agents, fn a ->
                %{
                  "name" => a.name,
                  "blocks" => a[:block_labels] || [],
                  "recall_count" => a[:recall_count] || 0,
                  "archival_count" => a[:archival_count] || 0
                }
              end)

            {:ok, entries}
        end
      end)
    end
  end
end
