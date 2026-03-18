defmodule Ichor.Tasks.BoardTest do
  use ExUnit.Case, async: false

  alias Ichor.Tasks.Board

  setup do
    team_name = "test-team-#{System.unique_integer([:positive])}"

    on_exit(fn ->
      File.rm_rf(Path.expand("~/.claude/tasks/#{team_name}"))
    end)

    %{team_name: team_name}
  end

  test "create, update, list, and delete task through board", %{team_name: team_name} do
    assert {:ok, task} =
             Board.create_task(team_name, %{
               "subject" => "Fix bug",
               "description" => "Investigate and fix",
               "status" => "pending"
             })

    assert task["id"] == "1"
    assert [%{"id" => "1"}] = Board.list_tasks(team_name)

    assert {:ok, updated} = Board.update_task(team_name, "1", %{"status" => "completed"})
    assert updated["status"] == "completed"

    assert :ok = Board.delete_task(team_name, "1")
    assert [] == Board.list_tasks(team_name)
  end
end
