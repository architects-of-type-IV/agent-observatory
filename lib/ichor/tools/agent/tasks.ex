defmodule Ichor.Tools.Agent.Tasks do
  @moduledoc """
  Task management tools for agents.
  """
  use Ash.Resource, domain: Ichor.Tools

  alias Ichor.Tasks.Board

  actions do
    action :get_tasks, {:array, :map} do
      description("Get your assigned tasks from the Ichor task board.")

      argument :session_id, :string do
        allow_nil?(false)
        description("Your agent session ID")
      end

      argument :team_name, :string do
        allow_nil?(true)
        description("Filter tasks by team name (optional)")
      end

      run(fn input, _context ->
        session_id = input.arguments.session_id
        team_name = input.arguments[:team_name]

        tasks =
          if team_name do
            Board.list_tasks(team_name)
          else
            []
          end

        my_tasks =
          tasks
          |> Enum.filter(fn task ->
            task["owner"] == session_id || task["owner"] == nil
          end)
          |> Enum.map(fn task ->
            %{
              "id" => task["id"],
              "subject" => task["subject"],
              "status" => task["status"],
              "owner" => task["owner"],
              "description" => task["description"]
            }
          end)

        {:ok, my_tasks}
      end)
    end

    action :update_task_status, :map do
      description("Update the status of a task you are working on.")

      argument :team_name, :string do
        allow_nil?(false)
        description("The team name the task belongs to")
      end

      argument :task_id, :string do
        allow_nil?(false)
        description("The task ID to update")
      end

      argument :status, :string do
        allow_nil?(false)
        description("New status: pending, in_progress, or completed")
      end

      run(fn input, _context ->
        team = input.arguments.team_name
        task_id = input.arguments.task_id
        status = input.arguments.status

        case Board.update_task(team, task_id, %{"status" => status}) do
          {:ok, task} ->
            {:ok,
             %{
               "status" => "updated",
               "task_id" => task_id,
               "new_status" => task["status"] || status
             }}

          {:error, reason} ->
            {:error, "Failed to update task: #{inspect(reason)}"}
        end
      end)
    end
  end
end
