defmodule Ichor.Tools.Agent.GenesisArtifacts do
  @moduledoc """
  MCP tools for creating and listing Genesis artifacts (ADRs, Features, UseCases,
  Checkpoints, Conversations) within a Node.
  """
  use Ash.Resource, domain: Ichor.Tools

  alias Ichor.Projects.{Adr, Feature, UseCase}
  alias Ichor.Tools.GenesisFormatter

  @valid_statuses %{
    "pending" => :pending,
    "proposed" => :proposed,
    "accepted" => :accepted,
    "rejected" => :rejected,
    "draft" => :draft
  }

  actions do
    action :create_adr, :map do
      description("Create an Architecture Decision Record for a Genesis Node.")

      argument(:node_id, :string, allow_nil?: false, description: "Genesis Node UUID")
      argument(:code, :string, allow_nil?: false, description: "ADR code, e.g. ADR-001")
      argument(:title, :string, allow_nil?: false, description: "ADR title")
      argument(:content, :string, allow_nil?: true, description: "ADR body text")

      argument(:status, :string,
        allow_nil?: true,
        description: "pending, proposed, accepted, or rejected"
      )

      run(fn input, _context ->
        args = input.arguments
        status = GenesisFormatter.parse_enum(args[:status], :pending, @valid_statuses)

        Adr.create(%{
          code: args.code,
          title: args.title,
          content: args[:content],
          status: status,
          node_id: args.node_id
        })
        |> to_map()
      end)
    end

    action :update_adr, :map do
      description("Update an existing ADR's status or content.")

      argument(:adr_id, :string, allow_nil?: false, description: "ADR UUID")
      argument(:status, :string, allow_nil?: true, description: "New status")
      argument(:content, :string, allow_nil?: true, description: "Updated body text")

      run(fn input, _context ->
        with {:ok, adr} <- Adr.get(input.arguments.adr_id) do
          attrs = %{}

          attrs =
            GenesisFormatter.put_if(
              attrs,
              :status,
              GenesisFormatter.parse_enum(input.arguments[:status], nil, @valid_statuses)
            )

          attrs = GenesisFormatter.put_if(attrs, :content, input.arguments[:content])
          Adr.update(adr, attrs) |> to_map()
        end
      end)
    end

    action :list_adrs, {:array, :map} do
      description("List all ADRs for a Genesis Node.")

      argument(:node_id, :string, allow_nil?: false, description: "Genesis Node UUID")

      run(fn input, _context ->
        with {:ok, adrs} <- Adr.by_node(input.arguments.node_id) do
          {:ok, Enum.map(adrs, &summarize_adr/1)}
        end
      end)
    end

    action :create_feature, :map do
      description("Create a Feature Requirements Document for a Genesis Node.")

      argument(:node_id, :string, allow_nil?: false, description: "Genesis Node UUID")
      argument(:code, :string, allow_nil?: false, description: "Feature code, e.g. FRD-001")
      argument(:title, :string, allow_nil?: false, description: "Feature title")
      argument(:content, :string, allow_nil?: true, description: "FRD body with inline FRs")
      argument(:adr_codes, :string, allow_nil?: true, description: "Comma-separated ADR codes")

      run(fn input, _context ->
        args = input.arguments
        adr_codes = GenesisFormatter.split_csv(args[:adr_codes])

        Feature.create(%{
          code: args.code,
          title: args.title,
          content: args[:content],
          adr_codes: adr_codes,
          node_id: args.node_id
        })
        |> to_map()
      end)
    end

    action :list_features, {:array, :map} do
      description("List all Features for a Genesis Node.")

      argument(:node_id, :string, allow_nil?: false, description: "Genesis Node UUID")

      run(fn input, _context ->
        with {:ok, features} <- Feature.by_node(input.arguments.node_id) do
          {:ok, Enum.map(features, &GenesisFormatter.summarize(&1, [:code, :title, :adr_codes]))}
        end
      end)
    end

    action :create_use_case, :map do
      description("Create a Use Case with Gherkin scenarios for a Genesis Node.")

      argument(:node_id, :string, allow_nil?: false, description: "Genesis Node UUID")
      argument(:code, :string, allow_nil?: false, description: "UC code, e.g. UC-0001")
      argument(:title, :string, allow_nil?: false, description: "Use case title")
      argument(:content, :string, allow_nil?: true, description: "UC body with Gherkin scenarios")

      argument(:feature_code, :string,
        allow_nil?: true,
        description: "Feature code this UC validates"
      )

      run(fn input, _context ->
        args = input.arguments

        UseCase.create(%{
          code: args.code,
          title: args.title,
          content: args[:content],
          feature_code: args[:feature_code],
          node_id: args.node_id
        })
        |> to_map()
      end)
    end

    action :list_use_cases, {:array, :map} do
      description("List all Use Cases for a Genesis Node.")

      argument(:node_id, :string, allow_nil?: false, description: "Genesis Node UUID")

      run(fn input, _context ->
        with {:ok, ucs} <- UseCase.by_node(input.arguments.node_id) do
          {:ok, Enum.map(ucs, &GenesisFormatter.summarize(&1, [:code, :title, :feature_code]))}
        end
      end)
    end
  end

  @artifact_fields ~w(id code title status content mode summary feature_code adr_codes node_id)a

  defp to_map(result), do: GenesisFormatter.to_map(result, @artifact_fields)

  defp summarize_adr(adr), do: GenesisFormatter.summarize(adr, [:code, :title, :status])
end
