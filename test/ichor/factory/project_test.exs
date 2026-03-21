defmodule Ichor.Factory.ProjectTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias Ichor.Factory.Project

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(Ichor.Repo)
  end

  defp base_attrs(overrides \\ %{}) do
    Map.merge(
      %{title: "Test Project", description: "A test project description"},
      overrides
    )
  end

  describe "create/1" do
    test "creates a project with required attributes" do
      assert {:ok, project} = Project.create(base_attrs())
      assert project.title == "Test Project"
      assert project.description == "A test project description"
      assert project.status == :proposed
      assert project.planning_stage == :discover
      assert project.output_kind == "plugin"
      assert project.version == "0.1.0"
    end

    test "creates project with optional fields" do
      assert {:ok, project} =
               Project.create(
                 base_attrs(%{
                   stakeholders: ["alice", "bob"],
                   constraints: ["budget < $1000"],
                   planning_stage: :define,
                   output_kind: "service",
                   plugin: "MyPlugin",
                   signal_interface: "signal_iface",
                   topic: "my:topic",
                   version: "1.0.0",
                   features: ["auth", "search"],
                   use_cases: ["UC-001"],
                   architecture: "monolith",
                   dependencies: ["ash"],
                   signals_emitted: ["factory:project_created"],
                   signals_subscribed: ["factory:run_started"]
                 })
               )

      assert project.stakeholders == ["alice", "bob"]
      assert project.planning_stage == :define
      assert project.output_kind == "service"
      assert project.plugin == "MyPlugin"
      assert project.features == ["auth", "search"]
    end

    test "rejects missing title" do
      assert {:error, _} = Project.create(%{description: "no title"})
    end

    test "rejects missing description" do
      assert {:error, _} = Project.create(%{title: "no description"})
    end

    test "rejects invalid status enum" do
      assert {:error, _} = Project.create(base_attrs(%{status: :bogus}))
    end

    test "rejects invalid planning_stage enum" do
      assert {:error, _} = Project.create(base_attrs(%{planning_stage: :unknown_stage}))
    end

    test "defaults status to :proposed" do
      {:ok, project} = Project.create(base_attrs())
      assert project.status == :proposed
    end
  end

  describe "update/2" do
    test "updates mutable fields" do
      {:ok, project} = Project.create(base_attrs())

      assert {:ok, updated} =
               Project.update(project, %{
                 title: "Updated Title",
                 description: "Updated desc",
                 features: ["new-feature"]
               })

      assert updated.title == "Updated Title"
      assert updated.features == ["new-feature"]
    end

    test "updates status directly" do
      {:ok, project} = Project.create(base_attrs())
      assert {:ok, updated} = Project.update(project, %{status: :in_progress})
      assert updated.status == :in_progress
    end
  end

  describe "get/1" do
    test "returns project by id" do
      {:ok, created} = Project.create(base_attrs())
      assert {:ok, fetched} = Project.get(created.id)
      assert fetched.id == created.id
    end

    test "returns error for non-existent id" do
      assert {:error, _} = Project.get(Ash.UUID.generate())
    end
  end

  describe "advance/2" do
    test "advances to the next planning stage" do
      {:ok, project} = Project.create(base_attrs())
      assert {:ok, advanced} = Project.advance(project, :define)
      assert advanced.planning_stage == :define
    end

    test "rejects invalid planning_stage" do
      {:ok, project} = Project.create(base_attrs())
      assert {:error, _} = Project.advance(project, :invalid_stage)
    end
  end

  describe "pick_up/2" do
    test "sets status to :in_progress and records who picked it up" do
      {:ok, project} = Project.create(base_attrs())
      assert {:ok, picked} = Project.pick_up(project, "session-123")
      assert picked.status == :in_progress
      assert picked.picked_up_by == "session-123"
      assert picked.picked_up_at != nil
    end
  end

  describe "mark_compiled/2" do
    test "sets status to :compiled with path" do
      {:ok, project} = Project.create(base_attrs())
      assert {:ok, compiled} = Project.mark_compiled(project, "/build/output")
      assert compiled.status == :compiled
      assert compiled.path == "/build/output"
    end
  end

  describe "mark_loaded/1" do
    test "sets status to :loaded" do
      {:ok, project} = Project.create(base_attrs())
      assert {:ok, loaded} = Project.mark_loaded(project)
      assert loaded.status == :loaded
    end
  end

  describe "mark_failed/2" do
    test "sets status to :failed with build_log" do
      {:ok, project} = Project.create(base_attrs())
      assert {:ok, failed} = Project.mark_failed(project, "compilation error on line 42")
      assert failed.status == :failed
      assert failed.build_log == "compilation error on line 42"
    end
  end

  describe "list_all/0" do
    test "returns all projects" do
      {:ok, p1} = Project.create(base_attrs(%{title: "Project A"}))
      {:ok, p2} = Project.create(base_attrs(%{title: "Project B"}))

      assert {:ok, projects} = Project.list_all()
      ids = Enum.map(projects, & &1.id)
      assert p1.id in ids
      assert p2.id in ids
    end
  end

  describe "by_status/1" do
    test "filters projects by status" do
      {:ok, proposed} = Project.create(base_attrs(%{title: "Proposed"}))
      {:ok, in_progress} = Project.create(base_attrs(%{title: "In Progress"}))
      Project.update(in_progress, %{status: :in_progress})

      assert {:ok, results} = Project.by_status(:proposed)
      ids = Enum.map(results, & &1.id)
      assert proposed.id in ids
    end
  end

  describe "create_project_draft/2 (generic action)" do
    test "creates project draft with title and description" do
      assert {:ok, result} = Project.create_project_draft("Draft Title", "Draft description")
      assert result["title"] == "Draft Title"
      assert is_binary(result["id"])
    end
  end

  describe "list_project_overviews/0 (generic action)" do
    test "returns a list of project overview maps" do
      {:ok, _} = Project.create(base_attrs(%{title: "Overview Project"}))
      assert {:ok, overviews} = Project.list_project_overviews()
      assert is_list(overviews)
    end
  end

  describe "get_project_overview/1 (generic action)" do
    test "returns a detailed project overview" do
      {:ok, project} = Project.create(base_attrs(%{title: "Detail Project"}))
      assert {:ok, result} = Project.get_project_overview(project.id)
      assert result["id"] == project.id
      assert result["title"] == "Detail Project"
    end
  end

  describe "gate_check/1 (generic action)" do
    test "returns a gate report map" do
      {:ok, project} = Project.create(base_attrs())
      assert {:ok, report} = Project.gate_check(project.id)
      assert is_map(report)
    end
  end

  describe "advance_project/2 (generic action)" do
    test "advances project planning stage" do
      {:ok, project} = Project.create(base_attrs())
      assert {:ok, result} = Project.advance_project(project.id, "define")
      assert result["planning_stage"] == "define"
    end

    test "rejects invalid planning stage string" do
      {:ok, project} = Project.create(base_attrs())
      assert {:error, _} = Project.advance_project(project.id, "nonexistent_stage")
    end
  end

  describe "embedded artifacts via create_adr/3" do
    test "creates an ADR artifact on the project" do
      {:ok, project} = Project.create(base_attrs())

      assert {:ok, adr} = Project.create_adr(project.id, "ADR-001", "Use SQLite")
      assert adr["code"] == "ADR-001"
      assert adr["title"] == "Use SQLite"
      assert adr["kind"] == "adr"
    end

    test "rejects missing code" do
      {:ok, project} = Project.create(base_attrs())
      assert {:error, _} = Project.create_adr(project.id, nil, "Title")
    end
  end

  describe "list_adrs/1" do
    test "returns ADR artifacts for a project" do
      {:ok, project} = Project.create(base_attrs())
      Project.create_adr(project.id, "ADR-001", "First ADR")
      Project.create_adr(project.id, "ADR-002", "Second ADR")

      assert {:ok, adrs} = Project.list_adrs(project.id)
      codes = Enum.map(adrs, & &1["code"])
      assert "ADR-001" in codes
      assert "ADR-002" in codes
    end

    test "returns empty list when no ADRs" do
      {:ok, project} = Project.create(base_attrs())
      assert {:ok, []} = Project.list_adrs(project.id)
    end
  end

  describe "embedded artifacts via create_feature/3" do
    test "creates a feature artifact on the project" do
      {:ok, project} = Project.create(base_attrs())

      # content and adr_codes are allow_nil?: false with default: "" but Ash maps "" -> nil,
      # so non-empty values must be supplied explicitly.
      assert {:ok, feature} =
               Project.create_feature(project.id, "F-001", "User auth", %{
                 content: "User authentication feature",
                 adr_codes: "ADR-001"
               })

      assert feature["code"] == "F-001"
      assert feature["title"] == "User auth"
      assert feature["kind"] == "feature"
    end
  end

  describe "list_features/1" do
    test "returns feature artifacts for a project" do
      {:ok, project} = Project.create(base_attrs())

      Project.create_feature(project.id, "F-001", "Feature One", %{
        content: "desc",
        adr_codes: "ADR-001"
      })

      Project.create_feature(project.id, "F-002", "Feature Two", %{
        content: "desc",
        adr_codes: "ADR-001"
      })

      assert {:ok, features} = Project.list_features(project.id)
      assert length(features) == 2
    end
  end

  describe "embedded artifacts via create_use_case/3" do
    test "creates a use case artifact on the project" do
      {:ok, project} = Project.create(base_attrs())

      # content and feature_code are allow_nil?: false with default: "" (maps to nil in Ash)
      assert {:ok, uc} =
               Project.create_use_case(project.id, "UC-001", "User logs in", %{
                 content: "The user enters credentials and is authenticated.",
                 feature_code: "F-001"
               })

      assert uc["code"] == "UC-001"
      assert uc["title"] == "User logs in"
      assert uc["kind"] == "use_case"
    end
  end

  describe "list_use_cases/1" do
    test "returns use case artifacts for a project" do
      {:ok, project} = Project.create(base_attrs())

      Project.create_use_case(project.id, "UC-001", "Log in", %{
        content: "desc",
        feature_code: "F-001"
      })

      Project.create_use_case(project.id, "UC-002", "Sign up", %{
        content: "desc",
        feature_code: "F-001"
      })

      assert {:ok, ucs} = Project.list_use_cases(project.id)
      assert length(ucs) == 2
    end
  end

  describe "embedded roadmap items via create_phase/3" do
    test "creates a phase roadmap item" do
      {:ok, project} = Project.create(base_attrs())

      # goals and governed_by are allow_nil?: false with default: "" (maps to nil in Ash)
      assert {:ok, phase} =
               Project.create_phase(project.id, 1, "Phase One", %{
                 goals: "Build the core",
                 governed_by: "ADR-001"
               })

      assert phase["number"] == 1
      assert phase["title"] == "Phase One"
      assert phase["kind"] == "phase"
      assert is_binary(phase["id"])
    end
  end

  describe "embedded roadmap items via create_section/4" do
    test "creates a section under a phase" do
      {:ok, project} = Project.create(base_attrs())

      {:ok, phase} =
        Project.create_phase(project.id, 1, "Phase One", %{
          goals: "Build core",
          governed_by: "ADR-001"
        })

      # goal is allow_nil?: false with default: "" (maps to nil in Ash)
      assert {:ok, section} =
               Project.create_section(phase["id"], project.id, 1, "Section One", %{
                 goal: "Build the section"
               })

      assert section["kind"] == "section"
      assert section["number"] == 1
      assert section["title"] == "Section One"
      assert section["parent_id"] == phase["id"]
    end
  end

  describe "embedded roadmap items via create_task/4" do
    test "creates a task under a section" do
      {:ok, project} = Project.create(base_attrs())

      {:ok, phase} =
        Project.create_phase(project.id, 1, "Phase One", %{
          goals: "Build core",
          governed_by: "ADR-001"
        })

      {:ok, section} =
        Project.create_section(phase["id"], project.id, 1, "Section One", %{
          goal: "Build section"
        })

      # governed_by and parent_uc are allow_nil?: false with default: "" (maps to nil in Ash)
      assert {:ok, task} =
               Project.create_task(section["id"], project.id, 1, "Task One", %{
                 governed_by: "ADR-001",
                 parent_uc: "UC-001"
               })

      assert task["kind"] == "task"
      assert task["title"] == "Task One"
      assert task["parent_id"] == section["id"]
    end
  end

  describe "embedded roadmap items via create_subtask/4" do
    test "creates a subtask under a task" do
      {:ok, project} = Project.create(base_attrs())

      {:ok, phase} =
        Project.create_phase(project.id, 1, "Phase One", %{
          goals: "Build core",
          governed_by: "ADR-001"
        })

      {:ok, section} =
        Project.create_section(phase["id"], project.id, 1, "Section One", %{
          goal: "Build section"
        })

      {:ok, task} =
        Project.create_task(section["id"], project.id, 1, "Task One", %{
          governed_by: "ADR-001",
          parent_uc: "UC-001"
        })

      # goal, allowed_files, blocked_by, steps, done_when, owner are allow_nil?: false
      # with default: "" (maps to nil in Ash) so non-empty values are required
      assert {:ok, subtask} =
               Project.create_subtask(task["id"], project.id, 1, "Subtask One", %{
                 goal: "Complete the subtask",
                 allowed_files: "lib/foo.ex",
                 blocked_by: "none",
                 steps: "Step 1",
                 done_when: "mix test",
                 owner: "agent-1"
               })

      assert subtask["kind"] == "subtask"
      assert subtask["title"] == "Subtask One"
      assert subtask["parent_id"] == task["id"]
    end
  end

  describe "list_phases/1" do
    test "returns hierarchical phases with children" do
      {:ok, project} = Project.create(base_attrs())

      {:ok, phase} =
        Project.create_phase(project.id, 1, "Phase One", %{
          goals: "Build core",
          governed_by: "ADR-001"
        })

      {:ok, _section} =
        Project.create_section(phase["id"], project.id, 1, "Section One", %{
          goal: "Build section"
        })

      assert {:ok, phases} = Project.list_phases(project.id)
      assert length(phases) == 1
      phase_result = hd(phases)
      assert phase_result["title"] == "Phase One"
      assert length(phase_result["children"]) == 1
    end

    test "returns empty list when no roadmap items" do
      {:ok, project} = Project.create(base_attrs())
      assert {:ok, []} = Project.list_phases(project.id)
    end
  end

  describe "create_checkpoint/3 (generic action)" do
    test "creates a checkpoint artifact" do
      {:ok, project} = Project.create(base_attrs())

      # content and summary are allow_nil?: false with default: "" (maps to nil in Ash)
      assert {:ok, cp} =
               Project.create_checkpoint(project.id, "Gate A", "gate_a", %{
                 content: "Gate A criteria",
                 summary: "Phase complete"
               })

      assert cp["kind"] == "checkpoint"
      assert cp["title"] == "Gate A"
    end
  end

  describe "create_conversation/3 (generic action)" do
    test "creates a conversation artifact" do
      {:ok, project} = Project.create(base_attrs())

      # content is allow_nil?: false with default: "" (maps to nil in Ash)
      assert {:ok, conv} =
               Project.create_conversation(project.id, "Design Discussion", "discover", %{
                 content: "Discussion notes"
               })

      assert conv["kind"] == "conversation"
      assert conv["title"] == "Design Discussion"
    end
  end

  describe "list_conversations/1 (generic action)" do
    test "returns conversation artifacts for a project" do
      {:ok, project} = Project.create(base_attrs())

      Project.create_conversation(project.id, "Conv 1", "discover", %{content: "notes"})
      Project.create_conversation(project.id, "Conv 2", "define", %{content: "notes"})

      assert {:ok, convs} = Project.list_conversations(project.id)
      assert length(convs) == 2
    end
  end

  describe "project with artifacts at create time" do
    test "creates project with pre-built embedded artifacts" do
      # Pre-built artifacts must NOT include :id since the embedded create action
      # does not accept it through the Ash simplified cast path.
      # Ash will auto-generate the UUID from the uuid_primary_key default.
      artifact = %{
        kind: :brief,
        title: "My Brief",
        content: "Here is the brief content"
      }

      assert {:ok, project} = Project.create(base_attrs(%{artifacts: [artifact]}))
      assert length(project.artifacts) == 1
      assert hd(project.artifacts).kind == :brief
      assert hd(project.artifacts).title == "My Brief"
    end

    test "creates project with pre-built roadmap items" do
      # Pre-built roadmap items must NOT include :id (same reason as artifacts above).
      item = %{
        kind: :phase,
        number: 1,
        title: "Phase One",
        status: :pending
      }

      assert {:ok, project} = Project.create(base_attrs(%{roadmap_items: [item]}))
      assert length(project.roadmap_items) == 1
      assert hd(project.roadmap_items).kind == :phase
    end
  end
end
