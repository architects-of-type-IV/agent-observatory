defmodule Ichor.Genesis.DagGenerator do
  @moduledoc """
  Converts a Genesis Node's Phase/Section/Task/Subtask hierarchy
  into tasks.jsonl format with blocked_by chains.

  Output: list of JSONL-compatible maps, one per subtask.
  Dotted IDs: "{phase_num}.{section_num}.{task_num}.{subtask_num}"
  """

  alias Ichor.Genesis.Phase

  @hierarchy_load [sections: [tasks: :subtasks]]

  @spec generate(String.t()) :: {:ok, [map()]} | {:error, term()}
  def generate(node_id) do
    with {:ok, phases} <- Phase.by_node(node_id),
         {:ok, loaded} <- Ash.load(phases, @hierarchy_load) do
      tasks =
        loaded
        |> flatten_hierarchy()
        |> build_uuid_to_dotted_map()
        |> convert_to_jsonl()

      {:ok, tasks}
    end
  end

  @spec to_jsonl_string([map()]) :: String.t()
  def to_jsonl_string(tasks) do
    Enum.map_join(tasks, "\n", &Jason.encode!/1)
  end

  # ── Private ──────────────────────────────────────────────────────

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

      blocked_by =
        (subtask.blocked_by || [])
        |> Enum.map(fn uuid -> Map.get(uuid_map, uuid, uuid) end)

      %{
        "id" => entry.dotted_id,
        "status" => to_string(subtask.status),
        "subject" => subtask.title,
        "goal" => subtask.goal,
        "files" => subtask.allowed_files || [],
        "done_when" => subtask.done_when,
        "blocked_by" => blocked_by,
        "steps" => subtask.steps || [],
        "owner" => subtask.owner || "",
        "tags" => [
          "phase-#{entry.phase.number}",
          "section-#{entry.section.number}"
        ],
        "feature" => entry.phase.title,
        "description" => build_description(entry),
        "created" => format_date(subtask.inserted_at)
      }
    end)
  end

  defp build_description(entry) do
    "Phase #{entry.phase.number}: #{entry.phase.title} > " <>
      "Section #{entry.section.number}: #{entry.section.title} > " <>
      "Task #{entry.task.number}: #{entry.task.title}"
  end

  defp format_date(nil), do: ""

  defp format_date(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d")
  end

  defp format_date(_), do: ""
end
