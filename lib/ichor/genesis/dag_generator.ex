defmodule Ichor.Genesis.DagGenerator do
  @moduledoc """
  Converts a Genesis Node's Phase/Section/Task/Subtask hierarchy
  into tasks.jsonl format with blocked_by chains.

  Output: list of JSONL-compatible maps, one per subtask.
  Dotted IDs: "{phase_num}.{section_num}.{task_num}.{subtask_num}"
  """

  @hierarchy_load [sections: [tasks: :subtasks]]
  @compile_gate "mix compile --warnings-as-errors"

  @doc "Generates a tasks.jsonl-compatible list of maps from a Genesis node hierarchy."
  @spec generate(String.t()) :: {:ok, [map()]} | {:error, term()}
  def generate(node_id) do
    with {:ok, node} <- Ichor.Projects.load_node(node_id, phases: @hierarchy_load) do
      tasks =
        node.phases
        |> flatten_hierarchy()
        |> build_uuid_to_dotted_map()
        |> convert_to_jsonl()

      {:ok, tasks}
    end
  end

  @doc "Encodes a list of task maps to a newline-delimited JSONL string."
  @spec to_jsonl_string([map()]) :: String.t()
  def to_jsonl_string(tasks) do
    Enum.map_join(tasks, "\n", &Jason.encode!/1)
  end

  defp flatten_hierarchy(phases) do
    for phase <- phases,
        section <- Enum.sort_by(phase.sections, & &1.number),
        task <- Enum.sort_by(section.tasks, & &1.number),
        subtask <- Enum.sort_by(task.subtasks, & &1.number) do
      %{
        phase: phase,
        section: section,
        task: task,
        subtask: subtask,
        dotted_id: "#{phase.number}.#{section.number}.#{task.number}.#{subtask.number}"
      }
    end
  end

  defp build_uuid_to_dotted_map(entries) do
    uuid_map =
      Map.new(entries, fn entry ->
        {entry.subtask.id, entry.dotted_id}
      end)

    {entries, uuid_map}
  end

  defp convert_to_jsonl({entries, uuid_map}) do
    Enum.map(entries, fn entry ->
      subtask = entry.subtask
      ts = format_date(subtask.inserted_at)

      blocked_by =
        (subtask.blocked_by || [])
        |> Enum.map(fn uuid -> Map.get(uuid_map, uuid, uuid) end)

      %{
        "id" => entry.dotted_id,
        "status" => to_string(subtask.status),
        "subject" => subtask.title,
        "description" => build_description(entry),
        "goal" => subtask.goal,
        "acceptance_criteria" => build_acceptance_criteria(subtask.done_when),
        "priority" => "high",
        "files" => subtask.allowed_files || [],
        "done_when" => subtask.done_when,
        "blocked_by" => blocked_by,
        "steps" => subtask.steps || [],
        "owner" => subtask.owner || "",
        "feature" => entry.phase.title,
        "tags" => [
          "phase-#{entry.phase.number}",
          "section-#{entry.section.number}"
        ],
        "roadmap_ref" => "#{entry.phase.number}.#{entry.section.number}",
        "created" => ts,
        "updated" => ts,
        "notes" => ""
      }
    end)
  end

  defp build_description(entry) do
    "Phase #{entry.phase.number}: #{entry.phase.title} > " <>
      "Section #{entry.section.number}: #{entry.section.title} > " <>
      "Task #{entry.task.number}: #{entry.task.title}"
  end

  defp build_acceptance_criteria(nil), do: [@compile_gate]
  defp build_acceptance_criteria(@compile_gate), do: [@compile_gate]
  defp build_acceptance_criteria(done_when), do: [@compile_gate, done_when]

  defp format_date(nil), do: ""
  defp format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%dT%H:%M:%SZ")
  defp format_date(_), do: ""
end
