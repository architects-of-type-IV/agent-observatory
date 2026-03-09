defmodule Ichor.Activity.Preparations.LoadTasks do
  @moduledoc """
  Loads tasks from TaskCreate/TaskUpdate hook events in the EventBuffer.
  """

  use Ash.Resource.Preparation

  @impl true
  def prepare(query, _opts, _context) do
    tasks =
      Ichor.EventBuffer.list_events()
      |> Enum.filter(fn e ->
        e.hook_event_type == :PreToolUse and e.tool_name in ["TaskCreate", "TaskUpdate"]
      end)
      |> Enum.sort_by(& &1.inserted_at, {:asc, DateTime})
      |> Enum.reduce(%{}, &reduce_task/2)
      |> Map.values()
      |> Enum.sort_by(& &1.id)
      |> Enum.map(&to_resource/1)

    Ash.DataLayer.Simple.set_data(query, tasks)
  end

  defp reduce_task(e, acc) do
    input = (e.payload || %{})["tool_input"] || %{}

    case e.tool_name do
      "TaskCreate" ->
        id = (map_size(acc) + 1) |> to_string()

        task = %{
          id: id,
          subject: input["subject"],
          description: input["description"],
          status: "pending",
          owner: nil,
          active_form: input["activeForm"],
          session_id: e.session_id,
          created_at: e.inserted_at
        }

        Map.put(acc, id, task)

      "TaskUpdate" ->
        task_id = input["taskId"]

        if task_id && Map.has_key?(acc, task_id) do
          task =
            acc[task_id]
            |> maybe_put(:status, input["status"])
            |> maybe_put(:owner, input["owner"])
            |> maybe_put(:subject, input["subject"])

          Map.put(acc, task_id, task)
        else
          acc
        end

      _ ->
        acc
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, val), do: Map.put(map, key, val)

  defp to_resource(task) do
    struct!(Ichor.Activity.Task, task)
  end
end
