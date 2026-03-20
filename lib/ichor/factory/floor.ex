defmodule Ichor.Factory.Floor do
  @moduledoc """
  Action-only Factory control surface for the task board and MES floor runtime.
  """

  use Ash.Resource, domain: Ichor.Factory

  alias Ichor.Factory.{Board, Runner, Scheduler, Spawn}
  alias Ichor.Workshop.ActiveTeam

  actions do
    action :get_tasks, {:array, :map} do
      description("Get assigned tasks from the Factory task board.")

      argument :session_id, :string do
        allow_nil?(false)
      end

      argument :team_name, :string do
        allow_nil?(false)
        default("")
      end

      run(fn input, _context ->
        session_id = input.arguments.session_id
        team_name = input.arguments.team_name

        tasks =
          case team_name do
            "" -> []
            name -> Board.list_tasks(name)
          end

        my_tasks =
          tasks
          |> Enum.filter(fn task -> task["owner"] == session_id or is_nil(task["owner"]) end)
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
      description("Update a Factory task status.")

      argument :team_name, :string do
        allow_nil?(false)
      end

      argument :task_id, :string do
        allow_nil?(false)
      end

      argument :status, :string do
        allow_nil?(false)
      end

      run(fn input, _context ->
        case Board.update_task(input.arguments.team_name, input.arguments.task_id, %{
               "status" => input.arguments.status
             }) do
          {:ok, task} ->
            {:ok,
             %{
               "status" => "updated",
               "task_id" => input.arguments.task_id,
               "new_status" => task["status"] || input.arguments.status
             }}

          {:error, reason} ->
            {:error, "Failed to update task: #{inspect(reason)}"}
        end
      end)
    end

    action :mes_status, :map do
      description("Get MES scheduler and run status.")

      run(fn _input, _context ->
        all_runs = Runner.list_all(:mes)

        run_details =
          Enum.map(all_runs, fn {run_id, pid} ->
            deadline_passed =
              try do
                GenServer.call(pid, :deadline_passed?, 1_000)
              catch
                :exit, _ -> true
              end

            %{
              "run_id" => run_id,
              "team" => "mes-#{run_id}",
              "alive" => Process.alive?(pid),
              "past_deadline" => deadline_passed
            }
          end)

        active_count = Enum.count(run_details, fn run -> not run["past_deadline"] end)

        scheduler_status =
          try do
            Scheduler.status()
          rescue
            _ -> %{error: "Scheduler not running"}
          end

        {:ok,
         %{
           "active_runs" => active_count,
           "total_runs" => length(all_runs),
           "runs" => run_details,
           "scheduler" => scheduler_status
         }}
      end)
    end

    action :cleanup_mes, :map do
      description("Force cleanup of orphaned MES teams and tmux sessions.")

      run(fn _input, _context ->
        try do
          Spawn.cleanup_orphaned_teams()
          {:ok, %{"status" => "cleanup_complete"}}
        rescue
          e -> {:ok, %{"status" => "error", "reason" => Exception.message(e)}}
        end
      end)
    end

    action :fleet_tasks, {:array, :map} do
      description("List board tasks across all active teams, or for a specific team.")

      argument :team_name, :string do
        allow_nil?(false)
        default("")
      end

      run(fn input, _context ->
        team_filter = Map.get(input.arguments, :team_name)

        teams =
          if team_filter in [nil, ""] do
            ActiveTeam.alive!()
          else
            ActiveTeam.alive!()
            |> Enum.filter(fn team -> team.name == team_filter end)
          end

        tasks =
          Enum.flat_map(teams, fn team ->
            Board.list_tasks(team.name)
            |> Enum.map(&Map.put(&1, "team", team.name))
          end)

        {:ok, tasks}
      end)
    end
  end

  code_interface do
    define(:get_tasks, args: [:session_id, :team_name])
    define(:update_task_status, args: [:team_name, :task_id, :status])
    define(:mes_status)
    define(:cleanup_mes)
    define(:fleet_tasks, args: [:team_name])
  end
end
