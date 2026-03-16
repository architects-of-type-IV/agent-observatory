defmodule Ichor.Genesis.DagGenerator do
  @moduledoc """
  Converts a Genesis Node's Phase/Section/Task/Subtask hierarchy
  into tasks.jsonl format with blocked_by chains.

  Output: list of JSONL-compatible maps, one per subtask.
  Dotted IDs: "{phase_num}.{section_num}.{task_num}.{subtask_num}"
  """

  alias Ichor.Genesis.{Phase, Section}
  alias Ichor.Genesis.Task, as: GTask

  @spec generate(String.t()) :: {:ok, [map()]} | {:error, term()}
  def generate(node_id) do
    with {:ok, phases} <- Phase.by_node(node_id) do
      tasks =
        phases
        |> load_hierarchy()
        |> build_uuid_to_dotted_map()
        |> convert_to_jsonl()

      {:ok, tasks}
    end
  end

  @spec to_jsonl_string([map()]) :: String.t()
  def to_jsonl_string(tasks) do
    tasks
    |> Enum.map(&Jason.encode!/1)
    |> Enum.join("\n")
  end

  # ── Private ──────────────────────────────────────────────────────

  defp load_hierarchy(phases) do
    Enum.flat_map(phases, fn phase ->
      sections = Section.by_phase!(phase.id)

      Enum.flat_map(sections, fn section ->
        tasks = GTask.by_section!(section.id)

        Enum.flat_map(tasks, fn task ->
          loaded = Ash.load!(task, [:subtasks])

          subtasks =
            loaded.subtasks
            |> Enum.sort_by(& &1.number)

          Enum.map(subtasks, fn subtask ->
            %{
              phase: phase,
              section: section,
              task: task,
              subtask: subtask,
              dotted_id: "#{phase.number}.#{section.number}.#{task.number}.#{subtask.number}"
            }
          end)
        end)
      end)
    end)
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
