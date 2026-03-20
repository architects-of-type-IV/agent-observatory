defmodule Ichor.Mesh.DecisionLog do
  @moduledoc """
  Universal message envelope transmitted by every agent in the Hypervisor network.

  Implemented as an Ecto embedded schema (not a database table) because DecisionLog
  instances are received as HTTP payloads, validated in memory, and forwarded over
  PubSub. They are never persisted directly to Postgres.

  Each section (meta, identity, cognition, action, state_delta, control) is stored
  as a plain `:map` field. These are internal transport envelopes; field-level
  validation is not required.

  See ADR-014 and FRD-006 for the full specification.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  @type t :: %__MODULE__{
          meta: map() | nil,
          identity: map() | nil,
          cognition: map() | nil,
          action: map() | nil,
          state_delta: map() | nil,
          control: map() | nil
        }

  embedded_schema do
    field :meta, :map
    field :identity, :map
    field :cognition, :map
    field :action, :map
    field :state_delta, :map
    field :control, :map
  end

  @doc """
  Builds a changeset for a DecisionLog from a string-keyed params map.

  All six sections are optional map fields.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(struct, params) do
    cast(struct, params, [:meta, :identity, :cognition, :action, :state_delta, :control])
  end

  @doc "True if the decision log has no parent step (i.e., it is a root node)."
  @spec root?(t()) :: boolean()
  def root?(%__MODULE__{meta: %{"parent_step_id" => nil}}), do: true
  def root?(%__MODULE__{meta: %{parent_step_id: nil}}), do: true
  def root?(%__MODULE__{meta: nil}), do: true
  def root?(%__MODULE__{}), do: false

  @doc "Parse the major version integer from the capability_version string."
  @spec major_version(t()) :: non_neg_integer() | nil
  def major_version(%__MODULE__{identity: identity}) when is_map(identity) do
    v = Map.get(identity, "capability_version") || Map.get(identity, :capability_version)
    parse_major(v)
  end

  def major_version(_), do: nil

  @doc """
  Overwrites `cognition.entropy_score` on a DecisionLog struct.

  Returns the log unchanged when `cognition` is nil.
  """
  @spec put_gateway_entropy_score(t(), float()) :: t()
  def put_gateway_entropy_score(%__MODULE__{cognition: nil} = log, _score), do: log

  def put_gateway_entropy_score(%__MODULE__{cognition: cognition} = log, score)
      when is_float(score) and is_map(cognition) do
    %{log | cognition: Map.put(cognition, :entropy_score, score)}
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

  defp parse_major(v) when is_binary(v) do
    case String.split(v, ".") do
      [major | _] -> String.to_integer(major)
      _ -> nil
    end
  end

  defp parse_major(_), do: nil
end
