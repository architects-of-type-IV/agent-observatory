defmodule Ichor.Factory.Artifact do
  @moduledoc """
  Embedded SDLC artifact stored inside a project.
  """

  use Ash.Resource, data_layer: :embedded

  attributes do
    uuid_primary_key(:id, writable?: true)

    attribute :kind, :atom do
      allow_nil?(false)
      public?(true)
      constraints(one_of: [:brief, :adr, :feature, :use_case, :checkpoint, :conversation])
    end

    attribute :title, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :content, :string do
      public?(true)
    end

    attribute :code, :string do
      public?(true)
    end

    attribute :status, :atom do
      public?(true)
      constraints(one_of: [:pending, :proposed, :accepted, :rejected])
    end

    attribute :mode, :atom do
      public?(true)
      constraints(one_of: [:discover, :define, :build, :gate_a, :gate_b, :gate_c])
    end

    attribute :summary, :string do
      public?(true)
    end

    attribute :adr_codes, {:array, :string} do
      public?(true)
      default([])
    end

    attribute :feature_code, :string do
      public?(true)
    end

    attribute :participants, {:array, :string} do
      public?(true)
      default([])
    end
  end
end
