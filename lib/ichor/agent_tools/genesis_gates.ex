defmodule Ichor.AgentTools.GenesisGates do
  @moduledoc """
  MCP tools for Genesis gate checkpoints and design conversations.
  """
  use Ash.Resource, domain: Ichor.Tools

  alias Ichor.Projects
  alias Ichor.Tools.GenesisFormatter

  @valid_modes %{
    "discover" => :discover,
    "define" => :define,
    "build" => :build,
    "gate_a" => :gate_a,
    "gate_b" => :gate_b,
    "gate_c" => :gate_c
  }

  actions do
    action :create_checkpoint, :map do
      description("Create a gate checkpoint recording readiness assessment.")

      argument(:node_id, :string, allow_nil?: false, description: "Genesis Node UUID")
      argument(:title, :string, allow_nil?: false, description: "Checkpoint title")
      argument(:mode, :string, allow_nil?: false, description: "Mode: discover, define, or build")
      argument(:content, :string, allow_nil?: true, description: "Gate check report")
      argument(:summary, :string, allow_nil?: true, description: "One-line verdict")

      run(fn input, _context ->
        args = input.arguments
        mode = Map.fetch!(@valid_modes, args.mode)

        Projects.create_checkpoint(%{
          title: args.title,
          mode: mode,
          content: args[:content],
          summary: args[:summary],
          node_id: args.node_id
        })
        |> to_map()
      end)
    end

    action :create_conversation, :map do
      description("Log a design conversation from a mode session.")

      argument(:node_id, :string, allow_nil?: false, description: "Genesis Node UUID")
      argument(:title, :string, allow_nil?: false, description: "Conversation title")
      argument(:mode, :string, allow_nil?: false, description: "Mode: discover, define, or build")
      argument(:content, :string, allow_nil?: true, description: "Transcript or summary")

      run(fn input, _context ->
        args = input.arguments
        mode = Map.fetch!(@valid_modes, args.mode)

        Projects.create_conversation(%{
          title: args.title,
          mode: mode,
          content: args[:content],
          node_id: args.node_id
        })
        |> to_map()
      end)
    end

    action :list_conversations, {:array, :map} do
      description("List all conversations for a Genesis Node.")

      argument(:node_id, :string, allow_nil?: false, description: "Genesis Node UUID")

      run(fn input, _context ->
        case Projects.conversations_by_node(input.arguments.node_id) do
          {:ok, convs} -> {:ok, Enum.map(convs, &GenesisFormatter.summarize(&1, [:title, :mode]))}
          error -> error
        end
      end)
    end
  end

  defp to_map(result),
    do: GenesisFormatter.to_map(result, [:title, :mode, :content, :summary, :node_id])
end
