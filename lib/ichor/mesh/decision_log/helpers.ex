defmodule Ichor.Mesh.DecisionLog.Helpers do
  @moduledoc """
  Pure helper functions for `Ichor.Mesh.DecisionLog` structs.

  Separate module required because Ash embedded resource structs are defined
  via `@before_compile`, making `%DecisionLog{}` struct patterns unavailable
  inside the resource module itself.
  """

  alias Ichor.Mesh.DecisionLog

  @type t :: DecisionLog.t()

  @doc """
  Deserializes a string-keyed map into a `%DecisionLog{}` struct.

  Returns `{:ok, %DecisionLog{}}`. All six sections are optional map fields.
  """
  @spec from_json(map()) :: {:ok, t()}
  def from_json(attrs) when is_map(attrs) do
    fields = %{
      meta: Map.get(attrs, "meta") || Map.get(attrs, :meta),
      identity: Map.get(attrs, "identity") || Map.get(attrs, :identity),
      cognition: Map.get(attrs, "cognition") || Map.get(attrs, :cognition),
      action: Map.get(attrs, "action") || Map.get(attrs, :action),
      state_delta: Map.get(attrs, "state_delta") || Map.get(attrs, :state_delta),
      control: Map.get(attrs, "control") || Map.get(attrs, :control)
    }

    {:ok, struct(DecisionLog, fields)}
  end

  @doc "True if the decision log has no parent step (i.e., it is a root node)."
  @spec root?(t()) :: boolean()
  def root?(%DecisionLog{meta: %{"parent_step_id" => nil}}), do: true
  def root?(%DecisionLog{meta: %{parent_step_id: nil}}), do: true
  def root?(%DecisionLog{meta: nil}), do: true
  def root?(%DecisionLog{}), do: false

  @doc "Parse the major version integer from the capability_version string."
  @spec major_version(t()) :: non_neg_integer() | nil
  def major_version(%DecisionLog{identity: identity}) when is_map(identity) do
    v = Map.get(identity, "capability_version") || Map.get(identity, :capability_version)
    parse_major(v)
  end

  def major_version(_), do: nil

  @doc """
  Overwrites `cognition.entropy_score` on a DecisionLog struct.

  Returns the log unchanged when `cognition` is nil.
  """
  @spec put_gateway_entropy_score(t(), float()) :: t()
  def put_gateway_entropy_score(%DecisionLog{cognition: nil} = log, _score), do: log

  def put_gateway_entropy_score(%DecisionLog{cognition: cognition} = log, score)
      when is_float(score) and is_map(cognition) do
    %{log | cognition: Map.put(cognition, :entropy_score, score)}
  end

  defp parse_major(v) when is_binary(v) do
    case String.split(v, ".") do
      [major | _] -> String.to_integer(major)
      _ -> nil
    end
  end

  defp parse_major(_), do: nil
end
