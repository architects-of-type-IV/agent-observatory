defmodule Ichor.Workshop.TeamMember do
  @moduledoc """
  A persisted team member definition for Workshop-authored teams.

  Each member may point at an `AgentType` while still carrying team-specific
  launch overrides like extra instructions, file scope, and tool scope.
  """

  use Ash.Resource,
    domain: Ichor.Workshop,
    data_layer: AshSqlite.DataLayer

  alias Ichor.Workshop.{AgentType, Team}

  sqlite do
    repo(Ichor.Repo)
    table("workshop_team_members")
  end

  attributes do
    uuid_primary_key(:id)

    attribute :slot, :integer do
      allow_nil?(false)
      public?(true)
    end

    attribute :position, :integer do
      allow_nil?(false)
      default(0)
      public?(true)
    end

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :capability, :string do
      allow_nil?(false)
      default("builder")
      public?(true)
    end

    attribute :model, :string do
      allow_nil?(false)
      default("sonnet")
      public?(true)
    end

    attribute :permission, :string do
      allow_nil?(false)
      default("default")
      public?(true)
    end

    attribute :extra_instructions, :string do
      allow_nil?(false)
      default("")
      public?(true)
    end

    attribute :file_scope, :string do
      allow_nil?(false)
      default("")
      public?(true)
    end

    attribute :quality_gates, :string do
      allow_nil?(false)
      default("")
      public?(true)
    end

    attribute :tool_scope, {:array, :string} do
      allow_nil?(false)
      default([])
      public?(true)
    end

    attribute :canvas_x, :integer do
      allow_nil?(false)
      default(40)
      public?(true)
    end

    attribute :canvas_y, :integer do
      allow_nil?(false)
      default(30)
      public?(true)
    end

    timestamps()
  end

  relationships do
    belongs_to :team, Team do
      source_attribute(:team_id)
      allow_nil?(false)
      attribute_public?(true)
    end

    belongs_to :agent_type, AgentType do
      allow_nil?(true)
      attribute_public?(true)
    end
  end

  identities do
    identity(:team_slot, [:team_id, :slot])
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)

      accept([
        :team_id,
        :agent_type_id,
        :slot,
        :position,
        :name,
        :capability,
        :model,
        :permission,
        :extra_instructions,
        :file_scope,
        :quality_gates,
        :tool_scope,
        :canvas_x,
        :canvas_y
      ])
    end

    update :update do
      primary?(true)

      accept([
        :agent_type_id,
        :position,
        :name,
        :capability,
        :model,
        :permission,
        :extra_instructions,
        :file_scope,
        :quality_gates,
        :tool_scope,
        :canvas_x,
        :canvas_y
      ])
    end

    read :for_team do
      argument(:team_id, :uuid, allow_nil?: false)
      filter(expr(team_id == ^arg(:team_id)))
      prepare(build(sort: [position: :asc, slot: :asc]))
    end

    read :for_team_with_type do
      argument(:team_id, :uuid, allow_nil?: false)
      filter(expr(team_id == ^arg(:team_id)))
      prepare(build(sort: [position: :asc, slot: :asc], load: [:agent_type]))
    end
  end

  code_interface do
    define(:create)
    define(:update)
    define(:destroy)
    define(:by_id, action: :read, get_by: [:id])
    define(:for_team, args: [:team_id])
    define(:for_team_with_type, args: [:team_id])
  end

  @doc "Replace all persisted members for a team from Workshop state."
  @spec sync_from_workshop_state(struct(), map()) :: :ok | {:error, term()}
  def sync_from_workshop_state(%Team{} = team, state) do
    existing = for_team!(team.id)

    Enum.each(existing, &destroy!/1)

    state
    |> Map.get(:ws_agents, [])
    |> Enum.with_index()
    |> Enum.each(fn {agent, index} ->
      create!(%{
        team_id: team.id,
        agent_type_id: agent[:agent_type_id],
        slot: agent.id,
        position: index,
        name: agent.name,
        capability: agent.capability,
        model: agent.model,
        permission: agent.permission,
        extra_instructions: agent.persona || "",
        file_scope: agent.file_scope || "",
        quality_gates: agent.quality_gates || "",
        tool_scope: Map.get(agent, :tools, []),
        canvas_x: agent.x,
        canvas_y: agent.y
      })
    end)

    :ok
  rescue
    error -> {:error, error}
  end
end
