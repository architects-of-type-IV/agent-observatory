defmodule Ichor.Mesh.DecisionLog do
  @moduledoc """
  Universal message envelope transmitted by every agent in the Hypervisor network.

  Implemented as an Ecto embedded schema (not a database table) because DecisionLog
  instances are received as HTTP payloads, validated in memory, and forwarded over
  PubSub. They are never persisted directly to Postgres.

  See ADR-014 and FRD-006 for the full specification.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Ichor.Mesh.DecisionLog.Action
  alias Ichor.Mesh.DecisionLog.Cognition
  alias Ichor.Mesh.DecisionLog.Control
  alias Ichor.Mesh.DecisionLog.Identity
  alias Ichor.Mesh.DecisionLog.Meta
  alias Ichor.Mesh.DecisionLog.StateDelta

  @primary_key false

  @type t :: %__MODULE__{
          meta: Meta.t() | nil,
          identity: Identity.t() | nil,
          cognition: Cognition.t() | nil,
          action: Action.t() | nil,
          state_delta: StateDelta.t() | nil,
          control: Control.t() | nil
        }

  embedded_schema do
    embeds_one :meta, Meta
    embeds_one :identity, Identity
    embeds_one :cognition, Cognition
    embeds_one :action, Action
    embeds_one :state_delta, StateDelta
    embeds_one :control, Control
  end

  @doc """
  Builds a changeset for a DecisionLog from a string-keyed params map.

  All six embedded sections are optional (cast_embed with required: false).
  Required fields within present sections are enforced by each sub-schema's
  own changeset function.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(struct, params) do
    struct
    |> cast(params, [])
    |> cast_embed(:meta, required: false, with: &Meta.changeset/2)
    |> cast_embed(:identity, required: false, with: &Identity.changeset/2)
    |> cast_embed(:cognition, required: false, with: &Cognition.changeset/2)
    |> cast_embed(:action, required: false, with: &Action.changeset/2)
    |> cast_embed(:state_delta, required: false, with: &StateDelta.changeset/2)
    |> cast_embed(:control, required: false, with: &Control.changeset/2)
  end

  @doc "True if the decision log has no parent step (i.e., it is a root node)."
  @spec root?(t()) :: boolean()
  def root?(%__MODULE__{meta: %{parent_step_id: nil}}), do: true
  def root?(%__MODULE__{}), do: false

  @doc "Parse the major version integer from the capability_version string."
  @spec major_version(t()) :: non_neg_integer() | nil
  def major_version(%__MODULE__{identity: %{capability_version: v}}) when is_binary(v) do
    case String.split(v, ".") do
      [major | _] -> String.to_integer(major)
      _ -> nil
    end
  end

  def major_version(_), do: nil

  @doc """
  Overwrites `cognition.entropy_score` on a DecisionLog struct.

  Returns the log unchanged when `cognition` is nil.
  """
  @spec put_gateway_entropy_score(t(), float()) :: t()
  def put_gateway_entropy_score(%__MODULE__{cognition: nil} = log, _score), do: log

  def put_gateway_entropy_score(%__MODULE__{cognition: cognition} = log, score)
      when is_float(score) do
    %{log | cognition: %{cognition | entropy_score: score}}
  end

  @doc """
  Deserializes a string-keyed map into a `%DecisionLog{}` struct.

  Returns `{:ok, %DecisionLog{}}` on success, `{:error, changeset}` on failure.
  """
  @spec from_json(map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def from_json(attrs) when is_map(attrs) do
    cs = changeset(%__MODULE__{}, attrs)
    if cs.valid?, do: {:ok, Ecto.Changeset.apply_changes(cs)}, else: {:error, cs}
  end
end
