defmodule Ichor.AgentTools.Agents do
  @moduledoc """
  Agent registration tools. Create and list memory-backed agents.
  """
  use Ash.Resource, domain: Ichor.AgentTools

  alias Ichor.MemoryStore

  actions do
    action :create_agent, :map do
      description "Register a new specialist agent with initial memory blocks."

      argument :agent_name, :string, allow_nil?: false
      argument :persona, :string, allow_nil?: false
      argument :human, :string, allow_nil?: true
      argument :extra_blocks, {:array, :map}, allow_nil?: true

      run fn input, _context ->
        args = input.arguments

        blocks = [
          %{label: "persona", value: args.persona, description: "Your persona and behavioral guidelines."},
          %{label: "human", value: args[:human] || "", description: "Key details about the human you work with."}
        ]

        extra =
          Enum.map(args[:extra_blocks] || [], fn b ->
            %{
              label: b["label"] || b[:label],
              value: b["value"] || b[:value] || "",
              description: b["description"] || b[:description] || ""
            }
          end)

        case MemoryStore.create_agent(args.agent_name, blocks ++ extra) do
          {:ok, agent} ->
            {:ok, %{"status" => "created", "agent" => agent.name, "blocks" => length(agent.block_ids)}}

          {:error, :already_exists} ->
            {:error, "Agent '#{args.agent_name}' already exists."}
        end
      end
    end

    action :list_agents, {:array, :map} do
      description "List all registered specialist agents with their memory block summaries."

      run fn _input, _context ->
        case MemoryStore.list_agents() do
          {:ok, agents} ->
            {:ok, Enum.map(agents, fn a ->
              %{"name" => a.name, "blocks" => a[:block_labels] || [],
                "recall_count" => a[:recall_count] || 0, "archival_count" => a[:archival_count] || 0}
            end)}
        end
      end
    end
  end
end
