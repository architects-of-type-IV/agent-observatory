defmodule Observatory.Mesh.DecisionLog do
  @moduledoc """
  Universal message envelope transmitted by every agent in the Hypervisor network.

  Implemented as an Ecto embedded schema (not a database table) because DecisionLog
  instances are received as HTTP payloads, validated in memory, and forwarded over
  PubSub. They are never persisted directly to Postgres.

  See ADR-014 and FRD-006 for the full specification.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  defmodule Meta do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :trace_id, :string
      field :timestamp, :utc_datetime
      field :parent_step_id, :string
      field :cluster_id, :string
    end

    @required_fields ~w(trace_id timestamp)a
    @optional_fields ~w(parent_step_id cluster_id)a

    def changeset(struct, params) do
      struct
      |> cast(params, @required_fields ++ @optional_fields)
      |> update_change(:parent_step_id, fn val -> if val == "", do: nil, else: val end)
      |> validate_required(@required_fields)
    end
  end

  defmodule Identity do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :agent_id, :string
      field :agent_type, :string
      field :capability_version, :string
    end

    @required_fields ~w(agent_id agent_type capability_version)a

    def changeset(struct, params) do
      struct
      |> cast(params, @required_fields)
      |> validate_required(@required_fields)
    end
  end

  defmodule Cognition do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :intent, :string
      field :reasoning_chain, {:array, :string}
      field :confidence_score, :float
      field :strategy_used, :string
      field :entropy_score, :float
    end

    @required_fields ~w(intent)a
    @optional_fields ~w(reasoning_chain confidence_score strategy_used entropy_score)a

    def changeset(struct, params) do
      struct
      |> cast(params, @required_fields ++ @optional_fields)
      |> validate_required(@required_fields)
    end
  end

  defmodule Action do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :status, Ecto.Enum, values: [:success, :failure, :pending, :skipped]
      field :tool_call, :string
      field :tool_input, :string
      field :tool_output_summary, :string
    end

    @required_fields ~w(status)a
    @optional_fields ~w(tool_call tool_input tool_output_summary)a

    def changeset(struct, params) do
      struct
      |> cast(params, @required_fields ++ @optional_fields)
      |> validate_required(@required_fields)
    end
  end

  defmodule StateDelta do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :added_to_memory, {:array, :string}
      field :tokens_consumed, :integer
      field :cumulative_session_cost, :float
    end

    @all_fields ~w(added_to_memory tokens_consumed cumulative_session_cost)a

    def changeset(struct, params) do
      cast(struct, params, @all_fields)
    end
  end

  defmodule Control do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :hitl_required, :boolean, default: false
      field :interrupt_signal, :string
      field :is_terminal, :boolean, default: false
    end

    @all_fields ~w(hitl_required interrupt_signal is_terminal)a

    def changeset(struct, params) do
      cast(struct, params, @all_fields)
    end
  end

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

  def root?(%__MODULE__{meta: %{parent_step_id: nil}}), do: true
  def root?(%__MODULE__{}), do: false

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
  def put_gateway_entropy_score(%__MODULE__{cognition: nil} = log, _score), do: log

  def put_gateway_entropy_score(%__MODULE__{cognition: cognition} = log, score)
      when is_float(score) do
    %{log | cognition: %{cognition | entropy_score: score}}
  end

  @doc """
  Deserializes a string-keyed map into a `%DecisionLog{}` struct.

  Returns `{:ok, %DecisionLog{}}` on success, `{:error, changeset}` on failure.
  """
  def from_json(attrs) when is_map(attrs) do
    cs = changeset(%__MODULE__{}, attrs)
    if cs.valid?, do: {:ok, Ecto.Changeset.apply_changes(cs)}, else: {:error, cs}
  end
end
