defmodule Ichor.AgentTools.GenesisNodes do
  @moduledoc """
  MCP tools for Genesis Node lifecycle management.
  """
  use Ash.Resource, domain: Ichor.AgentTools

  alias Ichor.Projects

  actions do
    action :create_genesis_node, :map do
      description("Create a new Genesis Node from a subsystem proposal. Starts in discover mode.")

      argument :title, :string do
        allow_nil?(false)
        description("Node title (subsystem name)")
      end

      argument :description, :string do
        allow_nil?(false)
        description("What this subsystem does")
      end

      argument :brief, :string do
        allow_nil?(true)
        description("Original MES brief content")
      end

      argument :mes_project_id, :string do
        allow_nil?(true)
        description("MES Project UUID that spawned this node")
      end

      run(fn input, _context ->
        args = input.arguments

        with {:ok, node} <-
               Projects.create_node(
                 Map.take(args, [:title, :description, :brief, :mes_project_id])
               ) do
          {:ok, summarize_node(node)}
        end
      end)
    end

    action :advance_node, :map do
      description("Advance a Genesis Node to the next pipeline stage.")

      argument :node_id, :string do
        allow_nil?(false)
        description("Genesis Node UUID")
      end

      argument :status, :string do
        allow_nil?(false)
        description("Target status: discover, define, build, or complete")
      end

      run(fn input, _context ->
        with {:ok, node} <- Projects.get_node(input.arguments.node_id),
             status <- String.to_existing_atom(input.arguments.status),
             {:ok, updated} <- Projects.advance_node(node.id, status) do
          {:ok, summarize_node(updated)}
        end
      end)
    end

    action :list_genesis_nodes, {:array, :map} do
      description("List all Genesis Nodes with their current pipeline status.")

      run(fn _input, _context ->
        case Projects.list_nodes() do
          {:ok, nodes} ->
            {:ok, Enum.map(nodes, &summarize_node/1)}

          error ->
            error
        end
      end)
    end

    action :get_genesis_node, :map do
      description("Get a Genesis Node with artifact counts.")

      argument :node_id, :string do
        allow_nil?(false)
        description("Genesis Node UUID")
      end

      run(fn input, _context ->
        with {:ok, loaded} <-
               Projects.load_node(input.arguments.node_id, [
                 :adrs,
                 :features,
                 :use_cases,
                 :checkpoints,
                 :conversations,
                 :phases
               ]) do
          {:ok, detail_node(loaded)}
        end
      end)
    end

    action :gate_check, :map do
      description(
        "Run a readiness check for advancing to the next pipeline stage. Returns artifact counts and missing items."
      )

      argument :node_id, :string do
        allow_nil?(false)
        description("Genesis Node UUID")
      end

      run(fn input, _context ->
        with {:ok, loaded} <-
               Projects.load_node(input.arguments.node_id, [
                 :adrs,
                 :features,
                 :use_cases,
                 :checkpoints,
                 :phases
               ]) do
          {:ok, gate_report(loaded)}
        end
      end)
    end
  end

  defp summarize_node(node) do
    %{
      "id" => node.id,
      "title" => node.title,
      "status" => to_string(node.status),
      "description" => node.description
    }
  end

  defp detail_node(node) do
    %{
      "id" => node.id,
      "title" => node.title,
      "status" => to_string(node.status),
      "description" => node.description,
      "adrs" => length(node.adrs),
      "features" => length(node.features),
      "use_cases" => length(node.use_cases),
      "checkpoints" => length(node.checkpoints),
      "conversations" => length(node.conversations),
      "phases" => length(node.phases)
    }
  end

  defp gate_report(node) do
    adrs = length(node.adrs)
    accepted_adrs = Enum.count(node.adrs, &(&1.status == :accepted))
    features = length(node.features)
    use_cases = length(node.use_cases)
    phases = length(node.phases)

    %{
      "node_id" => node.id,
      "current_status" => to_string(node.status),
      "adrs" => adrs,
      "accepted_adrs" => accepted_adrs,
      "features" => features,
      "use_cases" => use_cases,
      "checkpoints" => length(node.checkpoints),
      "phases" => phases,
      "ready_for_define" => adrs > 0 and accepted_adrs > 0,
      "ready_for_build" => features > 0 and use_cases > 0,
      "ready_for_complete" => phases > 0
    }
  end
end
