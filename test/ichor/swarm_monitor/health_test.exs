defmodule Ichor.SwarmMonitor.HealthTest do
  use ExUnit.Case, async: true

  alias Ichor.SwarmMonitor.Health

  test "parses health output into normalized map" do
    output =
      Jason.encode!(%{
        "healthy" => true,
        "agents" => %{"lead" => %{"status" => "ok"}},
        "issues" => %{
          "details" => [
            %{"type" => "stale", "severity" => "HIGH", "task_id" => "t1", "owner" => "lead"}
          ]
        }
      })

    assert {:ok, report} = Health.parse_health_output(output)
    assert report.healthy
    assert report.agents["lead"]["status"] == "ok"
    assert [%{type: "stale", severity: "HIGH", task_id: "t1"}] = report.issues
  end
end
