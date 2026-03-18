defmodule Ichor.SwarmMonitor.ProjectsTest do
  use ExUnit.Case, async: true

  alias Ichor.SwarmMonitor.Projects

  test "resolve tasks path for task project when available" do
    state = %{
      watched_projects: %{"alpha" => "/tmp/alpha", "beta" => "/tmp/beta"},
      active_project: "alpha",
      tasks: [%{id: "t-2", project: "beta"}]
    }

    assert Projects.tasks_jsonl_path(state) == "/tmp/alpha/tasks.jsonl"
    assert Projects.tasks_jsonl_path_for_task(state, "t-2") == "/tmp/beta/tasks.jsonl"
    assert Projects.tasks_jsonl_path_for_task(state, "missing") == "/tmp/alpha/tasks.jsonl"
  end

  test "resolve active project selection and refresh discovered projects" do
    state = %{
      watched_projects: %{"alpha" => "/tmp/alpha"},
      manual_projects: %{"manual" => "/tmp/manual"},
      active_project: "alpha"
    }

    assert {:ok, %{active_project: "alpha"}} = Projects.set_active_project(state, "alpha")
    assert {:error, :unknown_project} = Projects.set_active_project(state, "missing")

    {refreshed, changed?} = Projects.refresh_discovered_projects(state)
    assert changed? in [true, false]
    assert Map.has_key?(refreshed.manual_projects, "manual")
  end
end
