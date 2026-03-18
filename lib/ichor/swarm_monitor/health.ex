defmodule Ichor.SwarmMonitor.Health do
  @moduledoc """
  Health-check execution and report parsing for the swarm monitor.
  """

  require Logger

  @health_check_script Path.expand("~/.claude/skills/swarm/scripts/health-check.sh")

  def run(state, project_path) do
    if project_path && File.exists?(@health_check_script) do
      case run_health_script(project_path) do
        {:ok, health} -> %{state | health: health}
        :error -> state
      end
    else
      state
    end
  end

  def parse_health_output(output) do
    case Jason.decode(output) do
      {:ok, report} ->
        {:ok,
         %{
           healthy: report["healthy"] || false,
           issues: parse_issues(report),
           agents: report["agents"] || %{},
           timestamp: DateTime.utc_now()
         }}

      _ ->
        Logger.warning("SwarmMonitor: Failed to parse health report")
        :error
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

  defp parse_issues(report) do
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
