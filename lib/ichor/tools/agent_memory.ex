defmodule Ichor.Tools.AgentMemory do
  @moduledoc """
  Agent memory tools: core memory blocks, conversation recall, archival storage, and agent registration.
  """
  use Ash.Resource, domain: Ichor.Tools

  alias Ichor.MemoryStore

  actions do
    # --- Core memory ---

    action :read_memory, :map do
      description(
        "Read your core memory blocks. Returns all blocks pinned to your context. Call this first when starting a session."
      )

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

    action :memory_replace, :map do
      description("Replace text in a core memory block. Find old_text and replace with new_text.")

      argument(:agent_name, :string, allow_nil?: false)
      argument(:block_label, :string, allow_nil?: false)
      argument(:old_text, :string, allow_nil?: false)
      argument(:new_text, :string, allow_nil?: false)

      run(fn input, _context ->
        args = input.arguments

        case MemoryStore.memory_replace(
               args.agent_name,
               args.block_label,
               args.old_text,
               args.new_text
             ) do
          {:ok, block} ->
            {:ok,
             %{"status" => "replaced", "block" => args.block_label, "new_value" => block.value}}

          {:error, :text_not_found} ->
            {:error, "Text not found in block '#{args.block_label}'."}

          {:error, :read_only} ->
            {:error, "Block '#{args.block_label}' is read-only."}

          {:error, :exceeds_limit} ->
            {:error, "Replacement would exceed the block's character limit."}

          {:error, reason} ->
            {:error, "Failed: #{inspect(reason)}"}
        end
      end)
    end

    action :memory_insert, :map do
      description("Insert text at a specific line position in a core memory block.")

      argument(:agent_name, :string, allow_nil?: false)
      argument(:block_label, :string, allow_nil?: false)
      argument(:position, :integer, allow_nil?: false)
      argument(:text, :string, allow_nil?: false)

      run(fn input, _context ->
        args = input.arguments

        case MemoryStore.memory_insert(
               args.agent_name,
               args.block_label,
               args.position,
               args.text
             ) do
          {:ok, block} ->
            {:ok,
             %{"status" => "inserted", "block" => args.block_label, "new_value" => block.value}}

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
      description("Completely rewrite a core memory block with new content.")

      argument(:agent_name, :string, allow_nil?: false)
      argument(:block_label, :string, allow_nil?: false)
      argument(:new_value, :string, allow_nil?: false)

      run(fn input, _context ->
        args = input.arguments

        case MemoryStore.memory_rethink(args.agent_name, args.block_label, args.new_value) do
          {:ok, block} ->
            {:ok,
             %{"status" => "rewritten", "block" => args.block_label, "new_value" => block.value}}

          {:error, :read_only} ->
            {:error, "Block '#{args.block_label}' is read-only."}

          {:error, :exceeds_limit} ->
            {:error, "New content exceeds the block's character limit."}

          {:error, reason} ->
            {:error, "Failed: #{inspect(reason)}"}
        end
      end)
    end

    # --- Recall ---

    action :conversation_search, {:array, :map} do
      description(
        "Search your conversation history by text. Returns matching messages from past interactions."
      )

      argument(:agent_name, :string, allow_nil?: false)
      argument(:query, :string, allow_nil?: false)
      argument(:page, :integer, allow_nil?: false, default: 0)

      run(fn input, _context ->
        args = input.arguments

        case MemoryStore.conversation_search(args.agent_name, args.query, page: args.page) do
          {:ok, results} ->
            {:ok,
             Enum.map(results, fn e ->
               %{
                 "id" => e.id,
                 "role" => e.role,
                 "content" => e.content,
                 "timestamp" => e.timestamp
               }
             end)}

          {:error, reason} ->
            {:error, "Search failed: #{inspect(reason)}"}
        end
      end)
    end

    action :conversation_search_date, {:array, :map} do
      description("Search your conversation history by date range.")

      argument(:agent_name, :string, allow_nil?: false)
      argument(:start_date, :string, allow_nil?: false)
      argument(:end_date, :string, allow_nil?: false)

      run(fn input, _context ->
        args = input.arguments

        case MemoryStore.conversation_search_date(
               args.agent_name,
               args.start_date,
               args.end_date
             ) do
          {:ok, results} ->
            {:ok,
             Enum.map(results, fn e ->
               %{
                 "id" => e.id,
                 "role" => e.role,
                 "content" => e.content,
                 "timestamp" => e.timestamp
               }
             end)}

          {:error, reason} ->
            {:error, "Search failed: #{inspect(reason)}"}
        end
      end)
    end

    # --- Archival ---

    action :archival_memory_insert, :map do
      description(
        "Store information in your long-term archival memory. Tag entries for easier retrieval."
      )

      argument(:agent_name, :string, allow_nil?: false)
      argument(:content, :string, allow_nil?: false)
      argument(:tags, {:array, :string}, allow_nil?: false, default: [])

      run(fn input, _context ->
        args = input.arguments

        case MemoryStore.archival_memory_insert(args.agent_name, args.content, args.tags) do
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
      argument(:tags, {:array, :string}, allow_nil?: false, default: [])
      argument(:page, :integer, allow_nil?: false, default: 0)

      run(fn input, _context ->
        args = input.arguments

        case MemoryStore.archival_memory_search(args.agent_name, args.query,
               tags: args.tags,
               page: args.page
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

    # --- Agent registration ---

    action :create_agent, :map do
      description("Register a new specialist agent with initial memory blocks.")

      argument(:agent_name, :string, allow_nil?: false)
      argument(:persona, :string, allow_nil?: false)
      argument(:human, :string, allow_nil?: false, default: "")
      argument(:extra_blocks, {:array, :map}, allow_nil?: false, default: [])

      run(fn input, _context ->
        args = input.arguments

        blocks = [
          %{
            label: "persona",
            value: args.persona,
            description: "Your persona and behavioral guidelines."
          },
          %{
            label: "human",
            value: args.human,
            description: "Key details about the human you work with."
          }
        ]

        extra =
          Enum.map(args.extra_blocks, fn b ->
            %{
              label: b["label"] || b[:label],
              value: b["value"] || b[:value] || "",
              description: b["description"] || b[:description] || ""
            }
          end)

        case MemoryStore.create_agent(args.agent_name, blocks ++ extra) do
          {:ok, agent} ->
            {:ok,
             %{"status" => "created", "agent" => agent.name, "blocks" => length(agent.block_ids)}}

          {:error, :already_exists} ->
            {:error, "Agent '#{args.agent_name}' already exists."}
        end
      end)
    end

    action :list_registered_agents, {:array, :map} do
      description("List all registered specialist agents with their memory block summaries.")

      run(fn _input, _context ->
        case MemoryStore.list_agents() do
          {:ok, agents} ->
            {:ok,
             Enum.map(agents, fn a ->
               %{
                 "name" => a.name,
                 "blocks" => a[:block_labels] || [],
                 "recall_count" => a[:recall_count] || 0,
                 "archival_count" => a[:archival_count] || 0
               }
             end)}
        end
      end)
    end
  end
end
