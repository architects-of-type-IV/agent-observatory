defmodule Ichor.AgentTools.GenesisGates do
  @moduledoc """
  MCP tools for Genesis gate checkpoints and design conversations.
  """
  use Ash.Resource, domain: Ichor.AgentTools

  alias Ichor.Genesis.{Checkpoint, Conversation}

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
        mode = String.to_existing_atom(args.mode)

        Checkpoint.create(%{
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
        mode = String.to_existing_atom(args.mode)

        Conversation.create(%{
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
        case Conversation.by_node(input.arguments.node_id) do
          {:ok, convs} -> {:ok, Enum.map(convs, &summarize(&1, [:title, :mode]))}
          error -> error
        end
      end)
    end
  end

  defp to_map({:ok, record}) do
    Ichor.Signals.emit(:genesis_artifact_created, %{
      id: record.id,
      node_id: record.node_id,
      type: record.__struct__ |> Module.split() |> List.last() |> String.downcase()
    })

    {:ok,
     Map.take(record, [:id, :title, :mode, :content, :summary, :node_id])
     |> Map.new(fn {k, v} -> {to_string(k), stringify(v)} end)
     |> Map.reject(fn {_k, v} -> is_nil(v) end)}
  end

  defp to_map(error), do: error

  defp summarize(record, fields) do
    Map.new([:id | fields], fn field ->
      {to_string(field), stringify(Map.get(record, field))}
    end)
  end

  defp stringify(val) when is_atom(val), do: to_string(val)
  defp stringify(val), do: val
end
