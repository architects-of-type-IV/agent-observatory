defmodule Ichor.Tools.Archon.Mes do
  @moduledoc """
  MES floor management tools for Archon. Lists projects, creates briefs,
  checks operator inbox, and manages the manufacturing pipeline.
  """
  use Ash.Resource, domain: Ichor.Tools

  alias Ichor.Control.AgentProcess
  alias Ichor.Projects.{BuildRunner, Project, Scheduler, TeamLifecycle}

  @project_status_map %{
    "proposed" => :proposed,
    "in_progress" => :in_progress,
    "compiled" => :compiled,
    "loaded" => :loaded,
    "failed" => :failed
  }

  actions do
    action :list_projects, {:array, :map} do
      description(
        "List MES project briefs. Filter by status to see proposed, in_progress, compiled, loaded, or failed projects."
      )

      argument :status, :string do
        allow_nil?(false)

        description(
          "Filter by status: proposed, in_progress, compiled, loaded, failed. Empty string for all."
        )
      end

      run(fn input, _context ->
        projects =
          case input.arguments[:status] do
            s when s in [nil, ""] ->
              Project.list_all!()

            status_str ->
              case Map.fetch(@project_status_map, status_str) do
                {:ok, status} -> Project.by_status!(status)
                :error -> []
              end
          end

        {:ok, Enum.map(projects, &project_to_map/1)}
      end)
    end

    action :create_project, :map do
      description(
        "Create a new MES project brief. Use when an agent delivers a subsystem proposal or when you want to register a brief yourself."
      )

      argument :title, :string do
        allow_nil?(false)
        description("Short descriptive name for the subsystem")
      end

      argument :description, :string do
        allow_nil?(false)
        description("One or two sentence description of what it does")
      end

      argument :subsystem, :string do
        allow_nil?(false)
        description("Elixir module name (e.g. Ichor.Subsystems.EntropyHarvester)")
      end

      argument :signal_interface, :string do
        allow_nil?(false)
        description("How this subsystem is controlled through Ichor.Signals")
      end

      argument :topic, :string do
        allow_nil?(false)
        description("Unique PubSub topic (e.g. subsystem:correlator, empty string if none)")
      end

      argument :version, :string do
        allow_nil?(false)
        description("SemVer version string (default 0.1.0)")
      end

      argument :features, {:array, :string} do
        allow_nil?(false)
        description("List of capability descriptions (empty array if none)")
      end

      argument :use_cases, {:array, :string} do
        allow_nil?(false)
        description("Concrete scenarios where this subsystem is useful (empty array if none)")
      end

      argument :architecture, :string do
        allow_nil?(false)

        description(
          "Internal structure: processes, ETS tables, supervision (empty string if none)"
        )
      end

      argument :dependencies, {:array, :string} do
        allow_nil?(false)
        description("Ichor modules this subsystem requires (empty array if none)")
      end

      argument :signals_emitted, {:array, :string} do
        allow_nil?(false)
        description("Signal atoms this subsystem emits (empty array if none)")
      end

      argument :signals_subscribed, {:array, :string} do
        allow_nil?(false)

        description(
          "Signal atoms or categories this subsystem subscribes to (empty array if none)"
        )
      end

      argument :run_id, :string do
        allow_nil?(false)
        description("MES run ID that produced this brief (empty string if none)")
      end

      argument :team_name, :string do
        allow_nil?(false)
        description("MES team name that produced this brief (empty string if none)")
      end

      run(fn input, _context ->
        args = input.arguments

        attrs =
          %{
            title: args.title,
            description: args.description,
            subsystem: args.subsystem,
            signal_interface: args.signal_interface
          }
          |> maybe_put(:topic, args[:topic])
          |> maybe_put(:version, args[:version])
          |> maybe_put(:features, args[:features])
          |> maybe_put(:use_cases, args[:use_cases])
          |> maybe_put(:architecture, args[:architecture])
          |> maybe_put(:dependencies, args[:dependencies])
          |> maybe_put(:signals_emitted, args[:signals_emitted])
          |> maybe_put(:signals_subscribed, args[:signals_subscribed])
          |> maybe_put(:run_id, args[:run_id])
          |> maybe_put(:team_name, args[:team_name])

        case Project.create(attrs) do
          {:ok, project} -> {:ok, project_to_map(project)}
          {:error, reason} -> {:error, reason}
        end
      end)
    end

    action :check_operator_inbox, {:array, :map} do
      description(
        "Check messages sent to the operator by MES agents or other fleet members. This is YOUR inbox as floor manager. Messages are cleared after reading."
      )

      run(fn _input, _context ->
        try do
          messages = AgentProcess.get_unread("operator")

          formatted =
            Enum.map(messages, fn m ->
              %{
                "from" => m[:from] || m["from"],
                "content" => m[:content] || m["content"],
                "timestamp" => m[:timestamp] || m["timestamp"]
              }
            end)

          {:ok, formatted}
        rescue
          _ -> {:ok, []}
        end
      end)
    end

    action :mes_status, :map do
      description(
        "Get MES manufacturing pipeline status: active runs, scheduler state, team counts."
      )

      run(fn _input, _context ->
        all_runs = BuildRunner.list_all()
        active_runs = BuildRunner.list_active()

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

        scheduler_status =
          try do
            Scheduler.status()
          rescue
            _ -> %{error: "Scheduler not running"}
          end

        {:ok,
         %{
           "active_runs" => length(active_runs),
           "total_runs" => length(all_runs),
           "runs" => run_details,
           "scheduler" => scheduler_status
         }}
      end)
    end

    action :cleanup_mes, :map do
      description(
        "Force cleanup of orphaned MES teams and tmux sessions. Use when stale teams persist."
      )

      run(fn _input, _context ->
        try do
          TeamLifecycle.cleanup_orphaned_teams()
          {:ok, %{"status" => "cleanup_complete"}}
        rescue
          e -> {:ok, %{"status" => "error", "reason" => Exception.message(e)}}
        end
      end)
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp project_to_map(project) do
    %{
      "id" => project.id,
      "title" => project.title,
      "description" => project.description,
      "subsystem" => project.subsystem,
      "signal_interface" => project.signal_interface,
      "topic" => project.topic,
      "version" => project.version,
      "features" => project.features,
      "use_cases" => project.use_cases,
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
end
