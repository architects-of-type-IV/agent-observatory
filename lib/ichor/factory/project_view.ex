defmodule Ichor.Factory.ProjectView do
  @moduledoc """
  Pure serialization functions for Project records.

  Transforms `%Project{}` structs into string-keyed maps for MCP tool responses
  and API output. No Ash or database dependencies.
  """

  @artifact_fields ~w(id code title status content mode summary feature_code adr_codes kind)a

  @doc "Compact project summary for list views."
  @spec summarize(struct()) :: map()
  def summarize(project) do
    %{
      "id" => project.id,
      "title" => project.title,
      "output_kind" => project.output_kind,
      "planning_stage" => to_string(project.planning_stage),
      "status" => to_string(project.status),
      "description" => project.description
    }
  end

  @doc "Full project map for detail views."
  @spec to_map(struct()) :: map()
  def to_map(project) do
    %{
      "id" => project.id,
      "title" => project.title,
      "description" => project.description,
      "output_kind" => project.output_kind,
      "plugin" => project.plugin,
      "signal_interface" => project.signal_interface,
      "topic" => project.topic,
      "version" => project.version,
      "features" => artifact_titles(project, :feature),
      "use_cases" => artifact_titles(project, :use_case),
      "architecture" => project.architecture,
      "dependencies" => project.dependencies,
      "signals_emitted" => project.signals_emitted,
      "signals_subscribed" => project.signals_subscribed,
      "status" => to_string(project.status),
      "team_name" => project.team_name,
      "run_id" => project.run_id,
      "created_at" => project.inserted_at
    }
  end

  @doc "Project detail with artifact and roadmap counts."
  @spec detail(struct()) :: map()
  def detail(project) do
    %{
      "id" => project.id,
      "title" => project.title,
      "output_kind" => project.output_kind,
      "planning_stage" => to_string(project.planning_stage),
      "status" => to_string(project.status),
      "description" => project.description,
      "briefs" => count_artifacts(project.artifacts, :brief),
      "adrs" => count_artifacts(project.artifacts, :adr),
      "features" => count_artifacts(project.artifacts, :feature),
      "use_cases" => count_artifacts(project.artifacts, :use_case),
      "checkpoints" => count_artifacts(project.artifacts, :checkpoint),
      "conversations" => count_artifacts(project.artifacts, :conversation),
      "phases" => Enum.count(project.roadmap_items, &(&1.kind == :phase))
    }
  end

  @doc "Gate readiness report for planning stage transitions."
  @spec gate_report(struct()) :: map()
  def gate_report(project) do
    adrs = filter_artifacts(project.artifacts, :adr)
    accepted_adrs = Enum.count(adrs, &(&1.status == :accepted))
    features = count_artifacts(project.artifacts, :feature)
    use_cases = count_artifacts(project.artifacts, :use_case)
    checkpoints = count_artifacts(project.artifacts, :checkpoint)
    phases = Enum.count(project.roadmap_items, &(&1.kind == :phase))

    %{
      "project_id" => project.id,
      "output_kind" => project.output_kind,
      "planning_stage" => to_string(project.planning_stage),
      "adrs" => Enum.count(adrs),
      "accepted_adrs" => accepted_adrs,
      "features" => features,
      "use_cases" => use_cases,
      "checkpoints" => checkpoints,
      "phases" => phases,
      "ready_for_define" => adrs != [] and accepted_adrs > 0,
      "ready_for_build" => features > 0 and use_cases > 0,
      "ready_for_complete" => phases > 0
    }
  end

  @doc "Serialize an embedded item (artifact or roadmap) to a string-keyed map."
  @spec summarize_embedded(map(), [atom()]) :: map()
  def summarize_embedded(item, fields) do
    Map.new([:id | fields], fn field ->
      {to_string(field), stringify(Map.get(item, field))}
    end)
  end

  @doc "Serialize an embedded item with default artifact fields."
  @spec summarize_artifact(map()) :: map()
  def summarize_artifact(item), do: summarize_embedded(item, @artifact_fields)

  @doc "Serialize a roadmap tree node with children."
  @spec summarize_tree(map()) :: map()
  def summarize_tree(item) do
    base =
      item
      |> Map.take([
        :id,
        :kind,
        :number,
        :title,
        :status,
        :goal,
        :goals,
        :governed_by,
        :parent_uc,
        :allowed_files,
        :blocked_by,
        :steps,
        :done_when,
        :owner,
        :parent_id
      ])
      |> Enum.reject(fn {_key, value} -> is_nil(value) or value == [] end)
      |> Map.new(fn {key, value} -> {to_string(key), stringify(value)} end)

    case Map.get(item, :children, []) do
      [] -> base
      children -> Map.put(base, "children", Enum.map(children, &summarize_tree/1))
    end
  end

  @doc "Filter artifacts by kind."
  @spec filter_artifacts(list(), atom()) :: list()
  def filter_artifacts(artifacts, kind), do: Enum.filter(artifacts || [], &(&1.kind == kind))

  @doc "Extract artifact titles for a given kind."
  @spec artifact_titles(struct(), atom()) :: [String.t()]
  def artifact_titles(%{artifacts: artifacts}, kind) do
    artifacts
    |> filter_artifacts(kind)
    |> Enum.map(& &1.title)
    |> Enum.reject(&is_nil/1)
  end

  defp count_artifacts(artifacts, kind), do: Enum.count(artifacts || [], &(&1.kind == kind))

  defp stringify(value) when is_atom(value), do: to_string(value)
  defp stringify(value) when is_list(value), do: Enum.map(value, &stringify/1)
  defp stringify(value), do: value
end
