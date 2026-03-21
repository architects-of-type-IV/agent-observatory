defmodule Ichor.Factory.Project do
  @moduledoc """
  The durable MES project record.

  Project planning content lives inside the project as embedded data:
  briefs, SDLC artifacts, and roadmap items. It is not modeled as peer
  top-level resources.
  """

  use Ash.Resource,
    domain: Ichor.Factory,
    data_layer: AshSqlite.DataLayer,
    simple_notifiers: [Ichor.Signals.FromAsh]

  import Ichor.Util,
    only: [
      blank_to_nil: 1,
      empty_to_nil: 1,
      maybe_put: 3,
      split_csv: 1,
      split_lines: 1,
      parse_artifact_status: 1,
      parse_mode: 1
    ]

  alias Ichor.Factory.{Artifact, ProjectView, RoadmapItem}

  @project_status_map %{
    "proposed" => :proposed,
    "in_progress" => :in_progress,
    "compiled" => :compiled,
    "loaded" => :loaded,
    "failed" => :failed
  }

  @planning_stage_map %{
    "discover" => :discover,
    "define" => :define,
    "build" => :build,
    "complete" => :complete
  }

  @artifact_fields ~w(id code title status content mode summary feature_code adr_codes kind)a

  sqlite do
    repo(Ichor.Repo)
    table("projects")
  end

  attributes do
    uuid_primary_key(:id)

    attribute :title, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :description, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :stakeholders, {:array, :string} do
      public?(true)
      default([])
    end

    attribute :constraints, {:array, :string} do
      public?(true)
      default([])
    end

    attribute :planning_stage, :atom do
      allow_nil?(false)
      constraints(one_of: [:discover, :define, :build, :complete])
      default(:discover)
      public?(true)
    end

    attribute :output_kind, :string do
      allow_nil?(false)
      default("plugin")
      public?(true)
      description("What this MES project is expected to build")
    end

    attribute :plugin, :string do
      public?(true)
      description("Plugin module name")
    end

    attribute :signal_interface, :string do
      public?(true)
      description("How this plugin is controlled through Signals")
    end

    attribute :topic, :string do
      public?(true)
    end

    attribute :version, :string do
      public?(true)
      default("0.1.0")
    end

    attribute :features, {:array, :string} do
      public?(true)
      default([])
    end

    attribute :use_cases, {:array, :string} do
      public?(true)
      default([])
    end

    attribute :architecture, :string do
      public?(true)
    end

    attribute :dependencies, {:array, :string} do
      public?(true)
      default([])
    end

    attribute :signals_emitted, {:array, :string} do
      public?(true)
      default([])
    end

    attribute :signals_subscribed, {:array, :string} do
      public?(true)
      default([])
    end

    attribute :status, :atom do
      allow_nil?(false)
      constraints(one_of: [:proposed, :in_progress, :compiled, :loaded, :failed])
      default(:proposed)
      public?(true)
    end

    attribute :team_name, :string do
      public?(true)
    end

    attribute :run_id, :string do
      public?(true)
    end

    attribute :picked_up_by, :string do
      public?(true)
    end

    attribute :picked_up_at, :utc_datetime_usec do
      public?(true)
    end

    attribute :path, :string do
      public?(true)
    end

    attribute :build_log, :string do
      public?(true)
    end

    attribute :artifacts, {:array, Artifact} do
      public?(true)
      default([])
    end

    attribute :roadmap_items, {:array, RoadmapItem} do
      public?(true)
      default([])
    end

    timestamps()
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)

      accept([
        :title,
        :description,
        :stakeholders,
        :constraints,
        :planning_stage,
        :output_kind,
        :plugin,
        :signal_interface,
        :topic,
        :version,
        :features,
        :use_cases,
        :architecture,
        :dependencies,
        :signals_emitted,
        :signals_subscribed,
        :status,
        :team_name,
        :run_id,
        :picked_up_by,
        :picked_up_at,
        :path,
        :build_log,
        :artifacts,
        :roadmap_items
      ])
    end

    update :update do
      primary?(true)
      require_atomic?(false)

      accept([
        :title,
        :description,
        :stakeholders,
        :constraints,
        :planning_stage,
        :output_kind,
        :plugin,
        :signal_interface,
        :topic,
        :version,
        :features,
        :use_cases,
        :architecture,
        :dependencies,
        :signals_emitted,
        :signals_subscribed,
        :status,
        :team_name,
        :run_id,
        :picked_up_by,
        :picked_up_at,
        :path,
        :build_log,
        :artifacts,
        :roadmap_items
      ])
    end

    update :advance do
      accept([])

      argument :planning_stage, :atom do
        allow_nil?(false)
        constraints(one_of: [:discover, :define, :build, :complete])
      end

      change(set_attribute(:planning_stage, arg(:planning_stage)))
    end

    update :pick_up do
      accept([])

      argument :session_id, :string do
        allow_nil?(false)
      end

      change(set_attribute(:status, :in_progress))
      change(set_attribute(:picked_up_at, &DateTime.utc_now/0))
      change(set_attribute(:picked_up_by, arg(:session_id)))
    end

    update :mark_compiled do
      accept([])

      argument :path, :string do
        allow_nil?(false)
      end

      change(set_attribute(:status, :compiled))
      change(set_attribute(:path, arg(:path)))
    end

    update :mark_loaded do
      accept([])
      change(set_attribute(:status, :loaded))
    end

    update :mark_failed do
      accept([])

      argument :build_log, :string do
        allow_nil?(false)
      end

      change(set_attribute(:status, :failed))
      change(set_attribute(:build_log, arg(:build_log)))
    end

    action :create_project_draft, :map do
      description("Create a new project from a plugin proposal.")

      argument(:title, :string, allow_nil?: false)
      argument(:description, :string, allow_nil?: false)
      argument(:brief, :string, allow_nil?: false, default: "")
      argument(:output_kind, :string, allow_nil?: false, default: "plugin")
      argument(:plugin, :string, allow_nil?: false, default: "")
      argument(:signal_interface, :string, allow_nil?: false, default: "")
      argument(:topic, :string, allow_nil?: false, default: "")
      argument(:run_id, :string, allow_nil?: false, default: "")
      argument(:team_name, :string, allow_nil?: false, default: "")

      run(fn input, _context ->
        args = input.arguments

        attrs =
          %{
            title: args.title,
            description: args.description,
            artifacts: brief_artifacts(args.title, blank_to_nil(args.brief)),
            output_kind: args.output_kind
          }
          |> maybe_put(:plugin, blank_to_nil(args.plugin))
          |> maybe_put(:signal_interface, blank_to_nil(args.signal_interface))
          |> maybe_put(:topic, blank_to_nil(args.topic))
          |> maybe_put(:run_id, blank_to_nil(args.run_id))
          |> maybe_put(:team_name, blank_to_nil(args.team_name))

        with {:ok, project} <-
               __MODULE__
               |> Ash.Changeset.for_create(:create, attrs)
               |> Ash.create() do
          {:ok, ProjectView.summarize(project)}
        end
      end)
    end

    action :advance_project, :map do
      description("Advance a project to the next planning stage.")

      argument(:project_id, :string, allow_nil?: false)
      argument(:status, :string, allow_nil?: false)

      run(fn input, _context ->
        with {:ok, project} <- Ash.get(__MODULE__, input.arguments.project_id),
             {:ok, planning_stage} <- Map.fetch(@planning_stage_map, input.arguments.status),
             {:ok, updated} <-
               project
               |> Ash.Changeset.for_update(:advance, %{planning_stage: planning_stage})
               |> Ash.update() do
          {:ok, ProjectView.summarize(updated)}
        else
          :error -> {:error, "invalid planning stage: #{input.arguments.status}"}
          error -> error
        end
      end)
    end

    action :list_project_overviews, {:array, :map} do
      description("List all projects with their current planning stage.")

      run(fn _input, _context ->
        with {:ok, projects} <-
               __MODULE__
               |> Ash.Query.for_read(:list_all)
               |> Ash.read() do
          {:ok, Enum.map(projects, &ProjectView.summarize/1)}
        end
      end)
    end

    action :get_project_overview, :map do
      description("Get a project with artifact and roadmap counts.")

      argument(:project_id, :string, allow_nil?: false)

      run(fn input, _context ->
        with {:ok, project} <- Ash.get(__MODULE__, input.arguments.project_id) do
          {:ok, ProjectView.detail(project)}
        end
      end)
    end

    action :gate_check, :map do
      description("Get readiness signals for advancing the project.")

      argument(:project_id, :string, allow_nil?: false)

      run(fn input, _context ->
        with {:ok, project} <- Ash.get(__MODULE__, input.arguments.project_id) do
          {:ok, ProjectView.gate_report(project)}
        end
      end)
    end

    action :list_projects, {:array, :map} do
      description("List MES projects. Optionally filter by lifecycle status.")

      argument :status, :string do
        allow_nil?(false)
        default("")
      end

      run(fn input, _context ->
        projects =
          case input.arguments.status do
            "" ->
              __MODULE__
              |> Ash.Query.for_read(:list_all)
              |> Ash.read!()

            status_str ->
              case Map.fetch(@project_status_map, status_str) do
                {:ok, status} ->
                  __MODULE__
                  |> Ash.Query.for_read(:by_status, %{status: status})
                  |> Ash.read!()

                :error ->
                  []
              end
          end

        {:ok, Enum.map(projects, &ProjectView.to_map/1)}
      end)
    end

    action :create_project, :map do
      description("Create a MES project and initialize its brief artifact.")

      argument(:title, :string, allow_nil?: false)
      argument(:description, :string, allow_nil?: false)
      argument(:output_kind, :string, allow_nil?: false, default: "plugin")
      argument(:plugin, :string, allow_nil?: false)
      argument(:signal_interface, :string, allow_nil?: false)
      argument(:topic, :string, allow_nil?: false, default: "")
      argument(:version, :string, allow_nil?: false, default: "")
      argument(:features, {:array, :string}, allow_nil?: false, default: [])
      argument(:use_cases, {:array, :string}, allow_nil?: false, default: [])
      argument(:architecture, :string, allow_nil?: false, default: "")
      argument(:dependencies, {:array, :string}, allow_nil?: false, default: [])
      argument(:signals_emitted, {:array, :string}, allow_nil?: false, default: [])
      argument(:signals_subscribed, {:array, :string}, allow_nil?: false, default: [])
      argument(:run_id, :string, allow_nil?: false, default: "")
      argument(:team_name, :string, allow_nil?: false, default: "")

      run(fn input, _context ->
        args = input.arguments

        attrs =
          %{
            title: args.title,
            description: args.description,
            output_kind: args.output_kind,
            plugin: args.plugin,
            signal_interface: args.signal_interface,
            artifacts: brief_artifacts(args.title, render_project_brief(args))
          }
          |> maybe_put(:topic, blank_to_nil(args.topic))
          |> maybe_put(:version, blank_to_nil(args.version))
          |> maybe_put(:features, empty_to_nil(args.features))
          |> maybe_put(:use_cases, empty_to_nil(args.use_cases))
          |> maybe_put(:architecture, blank_to_nil(args.architecture))
          |> maybe_put(:dependencies, empty_to_nil(args.dependencies))
          |> maybe_put(:signals_emitted, empty_to_nil(args.signals_emitted))
          |> maybe_put(:signals_subscribed, empty_to_nil(args.signals_subscribed))
          |> maybe_put(:run_id, blank_to_nil(args.run_id))
          |> maybe_put(:team_name, blank_to_nil(args.team_name))

        case __MODULE__ |> Ash.Changeset.for_create(:create, attrs) |> Ash.create() do
          {:ok, project} -> {:ok, ProjectView.to_map(project)}
          {:error, reason} -> {:error, reason}
        end
      end)
    end

    action :create_adr, :map do
      description("Create an architecture decision record for a project.")

      argument(:project_id, :string, allow_nil?: false)
      argument(:code, :string, allow_nil?: false)
      argument(:title, :string, allow_nil?: false)
      argument(:content, :string, allow_nil?: false, default: "")
      argument(:status, :string, allow_nil?: false, default: "pending")

      run(fn input, _context ->
        args = input.arguments

        create_artifact_for(args.project_id, :adr, %{
          code: args.code,
          title: args.title,
          content: blank_to_nil(args.content),
          status: parse_artifact_status(args.status)
        })
      end)
    end

    action :update_adr, :map do
      description("Update an ADR status or content.")

      argument(:project_id, :string, allow_nil?: false)
      argument(:adr_id, :string, allow_nil?: false)
      argument(:status, :string, allow_nil?: false, default: "")
      argument(:content, :string, allow_nil?: false, default: "")

      run(fn input, _context ->
        with {:ok, project} <- Ash.get(__MODULE__, input.arguments.project_id),
             {:ok, updated} <-
               replace_artifact(project, input.arguments.adr_id, fn artifact ->
                 artifact
                 |> maybe_put(
                   :status,
                   parse_artifact_status(blank_to_nil(input.arguments.status))
                 )
                 |> maybe_put(:content, blank_to_nil(input.arguments.content))
               end) do
          {:ok,
           ProjectView.summarize_embedded(
             find_embedded!(updated.artifacts, input.arguments.adr_id),
             @artifact_fields
           )}
        end
      end)
    end

    action :list_adrs, {:array, :map} do
      description("List ADRs for a project.")

      argument(:project_id, :string, allow_nil?: false)

      run(fn input, _context ->
        list_artifacts_for(input.arguments.project_id, :adr, [:code, :title, :status])
      end)
    end

    action :create_feature, :map do
      description("Create a feature artifact for a project.")

      argument(:project_id, :string, allow_nil?: false)
      argument(:code, :string, allow_nil?: false)
      argument(:title, :string, allow_nil?: false)
      argument(:content, :string, allow_nil?: false, default: "")
      argument(:adr_codes, :string, allow_nil?: false, default: "")

      run(fn input, _context ->
        args = input.arguments

        create_artifact_for(args.project_id, :feature, %{
          code: args.code,
          title: args.title,
          content: blank_to_nil(args.content),
          adr_codes: split_csv(args.adr_codes)
        })
      end)
    end

    action :list_features, {:array, :map} do
      description("List features for a project.")

      argument(:project_id, :string, allow_nil?: false)

      run(fn input, _context ->
        list_artifacts_for(input.arguments.project_id, :feature, [:code, :title, :adr_codes])
      end)
    end

    action :create_use_case, :map do
      description("Create a use case artifact for a project.")

      argument(:project_id, :string, allow_nil?: false)
      argument(:code, :string, allow_nil?: false)
      argument(:title, :string, allow_nil?: false)
      argument(:content, :string, allow_nil?: false, default: "")
      argument(:feature_code, :string, allow_nil?: false, default: "")

      run(fn input, _context ->
        args = input.arguments

        create_artifact_for(args.project_id, :use_case, %{
          code: args.code,
          title: args.title,
          content: blank_to_nil(args.content),
          feature_code: blank_to_nil(args.feature_code)
        })
      end)
    end

    action :list_use_cases, {:array, :map} do
      description("List use cases for a project.")

      argument(:project_id, :string, allow_nil?: false)

      run(fn input, _context ->
        list_artifacts_for(input.arguments.project_id, :use_case, [:code, :title, :feature_code])
      end)
    end

    action :create_checkpoint, :map do
      description("Create a gate checkpoint artifact.")

      argument(:project_id, :string, allow_nil?: false)
      argument(:title, :string, allow_nil?: false)
      argument(:mode, :string, allow_nil?: false)
      argument(:content, :string, allow_nil?: false, default: "")
      argument(:summary, :string, allow_nil?: false, default: "")

      run(fn input, _context ->
        args = input.arguments

        create_artifact_for(
          args.project_id,
          :checkpoint,
          %{
            title: args.title,
            mode: parse_mode(args.mode),
            content: blank_to_nil(args.content),
            summary: blank_to_nil(args.summary)
          },
          [:kind, :title, :mode, :content, :summary]
        )
      end)
    end

    action :create_conversation, :map do
      description("Create a design conversation artifact.")

      argument(:project_id, :string, allow_nil?: false)
      argument(:title, :string, allow_nil?: false)
      argument(:mode, :string, allow_nil?: false)
      argument(:content, :string, allow_nil?: false, default: "")

      run(fn input, _context ->
        args = input.arguments

        create_artifact_for(
          args.project_id,
          :conversation,
          %{
            title: args.title,
            mode: parse_mode(args.mode),
            content: blank_to_nil(args.content)
          },
          [:kind, :title, :mode, :content]
        )
      end)
    end

    action :list_conversations, {:array, :map} do
      description("List design conversations for a project.")

      argument(:project_id, :string, allow_nil?: false)

      run(fn input, _context ->
        list_artifacts_for(input.arguments.project_id, :conversation, [:title, :mode])
      end)
    end

    action :create_phase, :map do
      description("Create a roadmap phase for a project.")

      argument(:project_id, :string, allow_nil?: false)
      argument(:number, :integer, allow_nil?: false)
      argument(:title, :string, allow_nil?: false)
      argument(:goals, :string, allow_nil?: false, default: "")
      argument(:governed_by, :string, allow_nil?: false, default: "")

      run(fn input, _context ->
        args = input.arguments

        create_roadmap_for(
          args.project_id,
          %{
            kind: :phase,
            number: args.number,
            title: args.title,
            goals: split_csv(args.goals),
            governed_by: split_csv(args.governed_by)
          },
          [:kind, :number, :title, :status, :goals, :governed_by]
        )
      end)
    end

    action :create_section, :map do
      description("Create a section within a phase.")

      argument(:phase_id, :string, allow_nil?: false)
      argument(:project_id, :string, allow_nil?: false)
      argument(:number, :integer, allow_nil?: false)
      argument(:title, :string, allow_nil?: false)
      argument(:goal, :string, allow_nil?: false, default: "")

      run(fn input, _context ->
        args = input.arguments

        create_roadmap_for(
          args.project_id,
          %{
            kind: :section,
            number: args.number,
            title: args.title,
            goal: blank_to_nil(args.goal),
            parent_id: args.phase_id
          },
          [:kind, :number, :title, :goal, :parent_id]
        )
      end)
    end

    action :create_task, :map do
      description("Create a task within a section.")

      argument(:section_id, :string, allow_nil?: false)
      argument(:project_id, :string, allow_nil?: false)
      argument(:number, :integer, allow_nil?: false)
      argument(:title, :string, allow_nil?: false)
      argument(:governed_by, :string, allow_nil?: false, default: "")
      argument(:parent_uc, :string, allow_nil?: false, default: "")

      run(fn input, _context ->
        args = input.arguments

        create_roadmap_for(
          args.project_id,
          %{
            kind: :task,
            number: args.number,
            title: args.title,
            governed_by: split_csv(args.governed_by),
            parent_uc: blank_to_nil(args.parent_uc),
            parent_id: args.section_id
          },
          [:kind, :number, :title, :status, :governed_by, :parent_uc, :parent_id]
        )
      end)
    end

    action :create_subtask, :map do
      description("Create a subtask within a task.")

      argument(:task_id, :string, allow_nil?: false)
      argument(:project_id, :string, allow_nil?: false)
      argument(:number, :integer, allow_nil?: false)
      argument(:title, :string, allow_nil?: false)
      argument(:goal, :string, allow_nil?: false, default: "")
      argument(:allowed_files, :string, allow_nil?: false, default: "")
      argument(:blocked_by, :string, allow_nil?: false, default: "")
      argument(:steps, :string, allow_nil?: false, default: "")
      argument(:done_when, :string, allow_nil?: false, default: "")
      argument(:owner, :string, allow_nil?: false, default: "")

      run(fn input, _context ->
        args = input.arguments

        create_roadmap_for(
          args.project_id,
          %{
            kind: :subtask,
            number: args.number,
            title: args.title,
            goal: blank_to_nil(args.goal),
            allowed_files: split_csv(args.allowed_files),
            blocked_by: split_csv(args.blocked_by),
            steps: split_lines(args.steps),
            done_when: blank_to_nil(args.done_when),
            owner: blank_to_nil(args.owner),
            parent_id: args.task_id
          },
          [
            :kind,
            :number,
            :title,
            :status,
            :goal,
            :allowed_files,
            :blocked_by,
            :steps,
            :done_when,
            :owner,
            :parent_id
          ]
        )
      end)
    end

    action :list_phases, {:array, :map} do
      description("List roadmap phases for a project.")

      argument(:project_id, :string, allow_nil?: false)

      run(fn input, _context ->
        with {:ok, project} <- Ash.get(__MODULE__, input.arguments.project_id) do
          {:ok, project.roadmap_items |> hierarchy() |> Enum.map(&ProjectView.summarize_tree/1)}
        end
      end)
    end

    read :list_all do
      prepare(build(sort: [inserted_at: :desc]))
    end

    read :by_status do
      argument :status, :atom do
        allow_nil?(false)
        constraints(one_of: [:proposed, :in_progress, :compiled, :loaded, :failed])
      end

      filter(expr(status == ^arg(:status)))
      prepare(build(sort: [inserted_at: :desc]))
    end
  end

  code_interface do
    define(:create)
    define(:update)
    define(:get, action: :read, get_by: [:id])
    define(:advance, args: [:planning_stage])
    define(:pick_up, args: [:session_id])
    define(:mark_compiled, args: [:path])
    define(:mark_loaded)
    define(:mark_failed, args: [:build_log])
    define(:list_all)
    define(:by_status, args: [:status])
    define(:create_project_draft, args: [:title, :description])
    define(:advance_project, args: [:project_id, :status])
    define(:list_project_overviews)
    define(:get_project_overview, args: [:project_id])
    define(:gate_check, args: [:project_id])
    define(:list_projects, args: [:status])

    define(:create_project,
      args: [:title, :description, :output_kind, :plugin, :signal_interface]
    )

    define(:create_adr, args: [:project_id, :code, :title])
    define(:update_adr, args: [:project_id, :adr_id])
    define(:list_adrs, args: [:project_id])
    define(:create_feature, args: [:project_id, :code, :title])
    define(:list_features, args: [:project_id])
    define(:create_use_case, args: [:project_id, :code, :title])
    define(:list_use_cases, args: [:project_id])
    define(:create_checkpoint, args: [:project_id, :title, :mode])
    define(:create_conversation, args: [:project_id, :title, :mode])
    define(:list_conversations, args: [:project_id])
    define(:create_phase, args: [:project_id, :number, :title])
    define(:create_section, args: [:phase_id, :project_id, :number, :title])
    define(:create_task, args: [:section_id, :project_id, :number, :title])
    define(:create_subtask, args: [:task_id, :project_id, :number, :title])
    define(:list_phases, args: [:project_id])
  end

  def hierarchy(items) do
    by_parent = Enum.group_by(items, & &1.parent_id)
    Enum.map(by_parent[nil] || [], &attach_children(&1, by_parent))
  end

  defdelegate artifact_titles(project, kind), to: ProjectView

  def latest_brief_text(%{artifacts: artifacts}), do: latest_brief_text(artifacts)

  def latest_brief_text(artifacts) when is_list(artifacts) do
    artifacts
    |> ProjectView.filter_artifacts(:brief)
    |> List.last()
    |> case do
      nil -> nil
      artifact -> artifact.content
    end
  end

  defp attach_children(item, by_parent) do
    Map.put(item, :children, Enum.map(by_parent[item.id] || [], &attach_children(&1, by_parent)))
  end

  defp create_artifact_for(project_id, kind, attrs, summary_fields \\ @artifact_fields) do
    with {:ok, project} <- Ash.get(__MODULE__, project_id),
         a <- artifact(attrs: Map.put(attrs, :kind, kind)),
         {:ok, updated} <- put_artifact(project, a) do
      # TODO: emit :project_artifact_created signal via a notifier once a pattern for
      # extracting the new artifact id and kind from the update notification is established.
      # The embedded artifact id (a.id) and kind are not derivable from the generic update
      # notification data without diffing the artifacts array.
      {:ok,
       ProjectView.summarize_embedded(find_embedded!(updated.artifacts, a.id), summary_fields)}
    end
  end

  defp list_artifacts_for(project_id, kind, summary_fields) do
    with {:ok, project} <- Ash.get(__MODULE__, project_id) do
      {:ok,
       project.artifacts
       |> ProjectView.filter_artifacts(kind)
       |> Enum.map(&ProjectView.summarize_embedded(&1, summary_fields))}
    end
  end

  defp create_roadmap_for(project_id, attrs, summary_fields) do
    with {:ok, project} <- Ash.get(__MODULE__, project_id),
         item <- roadmap_item(attrs),
         {:ok, updated} <- put_roadmap_item(project, item) do
      # TODO: emit :project_artifact_created signal via a notifier once a pattern for
      # extracting the new roadmap item id and kind from the update notification is established.
      # The embedded item id (item.id) and kind are not derivable from the generic update
      # notification data without diffing the roadmap_items array.
      {:ok,
       ProjectView.summarize_embedded(
         find_embedded!(updated.roadmap_items, item.id),
         summary_fields
       )}
    end
  end

  defp put_artifact(project, artifact) do
    project
    |> Ash.Changeset.for_update(:update, %{artifacts: (project.artifacts || []) ++ [artifact]})
    |> Ash.update()
  end

  defp replace_artifact(project, artifact_id, updater) do
    updated =
      Enum.map(project.artifacts || [], fn artifact ->
        if artifact.id == artifact_id, do: updater.(artifact), else: artifact
      end)

    project
    |> Ash.Changeset.for_update(:update, %{artifacts: updated})
    |> Ash.update()
  end

  defp put_roadmap_item(project, item) do
    project
    |> Ash.Changeset.for_update(:update, %{
      roadmap_items: (project.roadmap_items || []) ++ [item]
    })
    |> Ash.update()
  end

  defp brief_artifacts(_title, nil), do: []

  defp brief_artifacts(title, content) do
    [artifact(attrs: %{kind: :brief, title: title, content: content})]
  end

  defp artifact(attrs: attrs), do: Map.merge(%{id: Ash.UUID.generate()}, attrs)

  defp roadmap_item(attrs), do: Map.merge(%{id: Ash.UUID.generate(), status: :pending}, attrs)

  defp find_embedded!(items, id) do
    Enum.find(items || [], &(&1.id == id))
  end

  defp render_project_brief(args) do
    [
      {"Title", args.title},
      {"Description", args.description},
      {"Plugin", args.plugin},
      {"Signal Interface", args.signal_interface},
      {"Topic", blank_to_nil(args.topic)},
      {"Version", blank_to_nil(args.version)},
      {"Features", render_list(args.features)},
      {"Use Cases", render_list(args.use_cases)},
      {"Architecture", blank_to_nil(args.architecture)},
      {"Dependencies", render_list(args.dependencies)},
      {"Signals Emitted", render_list(args.signals_emitted)},
      {"Signals Subscribed", render_list(args.signals_subscribed)}
    ]
    |> Enum.reject(fn {_label, value} -> is_nil(value) or value == "" end)
    |> Enum.map_join("\n", fn {label, value} -> "#{label}: #{value}" end)
  end

  defp render_list([]), do: nil
  defp render_list(items) when is_list(items), do: Enum.join(items, ", ")
  defp render_list(value), do: value
end
