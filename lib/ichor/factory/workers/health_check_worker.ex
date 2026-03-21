defmodule Ichor.Factory.Workers.HealthCheckWorker do
  @moduledoc """
  Oban cron worker that runs the swarm health-check script and emits
  a `:pipeline_health` signal with the parsed results.

  Runs on the `:maintenance` queue every minute via Oban cron.
  The active project path is resolved at runtime from the EventStream CWDs.
  """

  use Oban.Worker, queue: :maintenance, max_attempts: 1, unique: [period: 55]

  require Logger

  alias Ichor.Factory.PipelineQuery
  alias Ichor.Signals

  @health_check_script Path.expand("~/.claude/skills/swarm/scripts/health-check.sh")

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    project_path = resolve_project_path()

    if project_path && valid_project_path?(project_path) && File.exists?(@health_check_script) do
      case run_health_script(project_path) do
        {:ok, health} ->
          Signals.emit(:pipeline_health, %{health: health})

        :error ->
          :ok
      end
    else
      :ok
    end
  end

  defp valid_project_path?(path) do
    String.starts_with?(path, "/") and File.dir?(path)
  end

  defp resolve_project_path do
    case PipelineQuery.projects() |> Map.values() do
      [path | _] -> path
      [] -> nil
    end
  end

  defp run_health_script(project_path) do
    case System.cmd("bash", [@health_check_script, project_path, "10"],
           stderr_to_stdout: true,
           env: []
         ) do
      {output, 0} -> parse_health_output(output)
      {_output, _code} -> :error
    end
  end

  defp parse_health_output(output) do
    case Jason.decode(output) do
      {:ok, report} ->
        {:ok,
         %{
           healthy: report["healthy"] || false,
           issues: parse_health_issues(report),
           agents: report["agents"] || %{},
           timestamp: DateTime.utc_now()
         }}

      _ ->
        Logger.warning("HealthCheckWorker: failed to parse health report output")
        :error
    end
  end

  defp parse_health_issues(report) do
    (get_in(report, ["issues", "details"]) || [])
    |> Enum.map(fn issue ->
      %{
        type: issue["type"] || "unknown",
        severity: issue["severity"] || "LOW",
        task_id: issue["task_id"],
        owner: issue["owner"],
        description: issue["description"] || "",
        details: issue
      }
    end)
  end
end
