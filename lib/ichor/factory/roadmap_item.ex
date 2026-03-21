defmodule Ichor.Factory.RoadmapItem do
  @moduledoc """
  Embedded roadmap item stored inside a project.

  The roadmap is a flat list with parent references; hierarchy is derived
  at runtime from `parent_id`.
  """

  use Ash.Resource, data_layer: :embedded

  attributes do
    uuid_primary_key(:id, writable?: true)

    attribute :kind, :atom do
      allow_nil?(false)
      public?(true)
      constraints(one_of: [:phase, :section, :task, :subtask])
    end

    attribute :number, :integer do
      allow_nil?(false)
      public?(true)
    end

    attribute :title, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :status, Ichor.Factory.Types.WorkStatus do
      allow_nil?(false)
      default(:pending)
      public?(true)
    end

    attribute :governed_by, {:array, :string} do
      public?(true)
      default([])
    end

    attribute :goals, {:array, :string} do
      public?(true)
      default([])
    end

    attribute :goal, :string do
      public?(true)
    end

    attribute :parent_uc, :string do
      public?(true)
    end

    attribute :allowed_files, {:array, :string} do
      public?(true)
      default([])
    end

    attribute :blocked_by, {:array, :string} do
      public?(true)
      default([])
    end

    attribute :steps, {:array, :string} do
      public?(true)
      default([])
    end

    attribute :done_when, :string do
      public?(true)
    end

    attribute :owner, :string do
      public?(true)
    end

    attribute :parent_id, :string do
      public?(true)
    end
  end
end
