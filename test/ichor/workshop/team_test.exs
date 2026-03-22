defmodule Ichor.Workshop.TeamTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Ichor.Workshop.Team

  setup do
    :ok = Sandbox.checkout(Ichor.Repo)
  end

  describe "create" do
    test "creates a team with valid name" do
      assert {:ok, team} = Team.create(%{name: "test-#{System.unique_integer([:positive])}"})
      assert team.name != nil
    end

    test "applies strategy default" do
      assert {:ok, team} = Team.create(%{name: "strat-#{System.unique_integer([:positive])}"})
      assert team.strategy == "one_for_one"
    end

    test "applies default_model default" do
      assert {:ok, team} = Team.create(%{name: "model-#{System.unique_integer([:positive])}"})
      assert team.default_model == "sonnet"
    end

    test "accepts custom strategy and model" do
      assert {:ok, team} =
               Team.create(%{
                 name: "custom-#{System.unique_integer([:positive])}",
                 strategy: "one_for_all",
                 default_model: "opus"
               })

      assert team.strategy == "one_for_all"
      assert team.default_model == "opus"
    end

    test "rejects missing name" do
      assert {:error, _} = Team.create(%{})
    end

    test "rejects duplicate name" do
      name = "dup-#{System.unique_integer([:positive])}"
      assert {:ok, _} = Team.create(%{name: name})
      assert {:error, _} = Team.create(%{name: name})
    end
  end

  describe "read" do
    test "reads all teams" do
      assert {:ok, teams} = Team.read()
      assert is_list(teams)
    end

    test "finds team by name" do
      name = "find-#{System.unique_integer([:positive])}"
      {:ok, created} = Team.create(%{name: name})
      assert {:ok, found} = Team.by_name(name)
      assert found.id == created.id
    end

    test "by_name returns error for missing team" do
      assert {:error, _} = Team.by_name("nonexistent-#{System.unique_integer([:positive])}")
    end

    test "by_id finds team by uuid" do
      {:ok, created} = Team.create(%{name: "byid-#{System.unique_integer([:positive])}"})
      assert {:ok, found} = Team.by_id(created.id)
      assert found.id == created.id
    end

    test "list_all returns teams sorted newest first" do
      name_a = "lst-a-#{System.unique_integer([:positive])}"
      name_b = "lst-b-#{System.unique_integer([:positive])}"
      {:ok, _} = Team.create(%{name: name_a})
      {:ok, _} = Team.create(%{name: name_b})
      assert {:ok, teams} = Team.list_all()
      assert is_list(teams)
      # Newest first: inserted_at desc
      inserted_ats = Enum.map(teams, & &1.inserted_at)
      assert inserted_ats == Enum.sort(inserted_ats, &(DateTime.compare(&1, &2) != :lt))
    end
  end

  describe "update" do
    test "updates team name" do
      {:ok, team} = Team.create(%{name: "upd-#{System.unique_integer([:positive])}"})
      new_name = "updated-#{System.unique_integer([:positive])}"
      assert {:ok, updated} = Team.update(team, %{name: new_name})
      assert updated.name == new_name
    end

    test "updates strategy" do
      {:ok, team} = Team.create(%{name: "strat-upd-#{System.unique_integer([:positive])}"})
      assert {:ok, updated} = Team.update(team, %{strategy: "rest_for_one"})
      assert updated.strategy == "rest_for_one"
    end

    test "updates cwd" do
      {:ok, team} = Team.create(%{name: "cwd-upd-#{System.unique_integer([:positive])}"})
      assert {:ok, updated} = Team.update(team, %{cwd: "/some/path"})
      assert updated.cwd == "/some/path"
    end
  end

  describe "destroy" do
    test "destroys a team" do
      {:ok, team} = Team.create(%{name: "del-#{System.unique_integer([:positive])}"})
      assert :ok = Team.destroy(team)
    end

    test "destroyed team is no longer found by name" do
      name = "gone-#{System.unique_integer([:positive])}"
      {:ok, team} = Team.create(%{name: name})
      :ok = Team.destroy(team)
      assert {:error, _} = Team.by_name(name)
    end
  end
end
