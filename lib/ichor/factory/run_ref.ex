defmodule Ichor.Factory.RunRef do
  @moduledoc "Typed run reference. Consolidates kind + run_id dispatch."

  @type t :: %__MODULE__{kind: :mes | :pipeline | :planning, run_id: String.t()}
  defstruct [:kind, :run_id]

  @doc "Builds a RunRef from a kind atom and run_id string."
  @spec new(:mes | :pipeline | :planning, String.t()) :: t()
  def new(kind, run_id) when kind in [:mes, :pipeline, :planning],
    do: %__MODULE__{kind: kind, run_id: run_id}

  @doc """
  Parses a prefixed session string into a RunRef.

  Recognises:
    - `"mes-{run_id}"`
    - `"pipeline-{run_id}"`
    - `"planning-{mode}-{run_id}"`
  """
  @spec parse(String.t()) :: {:ok, t()} | :error
  def parse("mes-" <> run_id), do: {:ok, %__MODULE__{kind: :mes, run_id: run_id}}
  def parse("pipeline-" <> run_id), do: {:ok, %__MODULE__{kind: :pipeline, run_id: run_id}}

  def parse("planning-" <> rest) do
    case String.split(rest, "-", parts: 2) do
      [_mode, run_id] -> {:ok, %__MODULE__{kind: :planning, run_id: run_id}}
      _ -> :error
    end
  end

  def parse(_), do: :error

  @doc "Returns the tmux session name for a run reference."
  @spec session_name(t()) :: String.t()
  def session_name(%__MODULE__{kind: :mes, run_id: id}), do: "mes-#{id}"
  def session_name(%__MODULE__{kind: :pipeline, run_id: id}), do: "pipeline-#{id}"
  def session_name(%__MODULE__{kind: :planning, run_id: id}), do: "planning-#{id}"

  @doc "Returns the Registry key atom for a run kind."
  @spec registry_key(:mes | :pipeline | :planning) :: atom()
  def registry_key(:mes), do: :run
  def registry_key(:planning), do: :planning_run
  def registry_key(:pipeline), do: :pipeline_run

  @doc "Returns the DynamicSupervisor module for a run kind."
  @spec supervisor(:mes | :pipeline | :planning) :: module()
  def supervisor(:mes), do: Ichor.Factory.BuildRunSupervisor
  def supervisor(:planning), do: Ichor.Factory.PlanRunSupervisor
  def supervisor(:pipeline), do: Ichor.Factory.DynRunSupervisor
end
