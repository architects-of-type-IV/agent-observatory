defmodule Ichor.Factory.Validator do
  @moduledoc "Pipeline graph validation. Detects cycles, missing dependencies, and structural issues in task DAGs."

  alias Ichor.Factory.{PipelineGraph, PipelineTask}

  @type validation_result :: %{
          cycles: [{String.t(), String.t()}],
          missing_refs: [{String.t(), [String.t()]}]
        }

  @doc "Validates a pipeline by run ID. Returns ok if graph is acyclic and all deps are present."
  @spec validate_pipeline(String.t()) ::
          {:ok, validation_result()} | {:error, validation_result()}
  def validate_pipeline(run_id) do
    with {:ok, pipeline_tasks} <- PipelineTask.by_run(run_id) do
      items = Enum.map(pipeline_tasks, &PipelineGraph.to_graph_node/1)
      cycles = detect_cycles(items)
      missing = flat_pipeline_check(items)

      if cycles == [] and missing == [] do
        {:ok, %{cycles: [], missing_refs: []}}
      else
        {:error, %{cycles: cycles, missing_refs: missing}}
      end
    end
  end

  @doc "Detects two-node cycles (A -> B and B -> A) in a list of graph nodes."
  @spec detect_cycles([map()]) :: [{String.t(), String.t()}]
  def detect_cycles(items) do
    edges = for item <- items, dep <- item.blocked_by, do: {item.id, dep}

    for {a, b} <- edges,
        {^b, ^a} <- edges,
        a < b,
        do: {a, b}
  end

  @doc "Returns tasks that reference dependency IDs not present in the node list."
  @spec flat_pipeline_check([map()]) :: [{String.t(), [String.t()]}]
  def flat_pipeline_check(items) do
    known_ids = MapSet.new(items, & &1.id)

    items
    |> Enum.map(fn %{id: id, blocked_by: deps} ->
      missing = Enum.reject(deps, &MapSet.member?(known_ids, &1))
      {id, missing}
    end)
    |> Enum.reject(fn {_id, missing} -> missing == [] end)
  end
end
