defmodule Ichor.Tools.Agent.Memory do
  @moduledoc """
  Core memory tools for agents. Read and edit in-context memory blocks.
  """
  use Ash.Resource, domain: Ichor.Tools

  alias Ichor.MemoryStore

  actions do
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
  end
end
