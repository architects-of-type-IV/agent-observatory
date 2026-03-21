defmodule Ichor.Factory.Spawn do
  @moduledoc """
  Spawns execution teams for pipeline and planning runs.

  Consolidates pipeline spawn (formerly Spawner) and planning mode spawn (formerly
  ModeSpawner) into a single module. Per-mode differences are expressed as
  data: session prefix, spec builder args, pre-launch steps.

  Incorporates: Loader, Validator, WorkerGroups.

  Public API:
    - spawn(:pipeline, project_id, project_id)
    - spawn(:planning, mode, project_id, project_id)
    - ensure_planning_project(project_id_or_nil, project)
    - load_project_brief(project_id)
    - from_file/2
    - from_project/2
  """

  alias Ichor.Infrastructure.TeamLaunch

  alias Ichor.Factory.{
    Pipeline,
    PipelineCompiler,
    PipelineGraph,
    PipelineTask,
    Project,
    Runner
  }

  alias Ichor.Factory.PluginScaffold
  alias Ichor.Signals
  alias Ichor.Workshop.TeamSpec

  # ---------------------------------------------------------------------------
  # Pipeline spawn
  # ---------------------------------------------------------------------------

  @doc "Spawns a full pipeline execution team for the given project."
  @spec spawn(:pipeline, String.t(), String.t()) ::
          {:ok, %{session: String.t(), run: map()}} | {:error, term()}
  def spawn(:pipeline, project_id, _selected_project_id) do
    session = "pipeline-#{short_id()}"
    brief = load_project_brief(project_id)

    with {:ok, project} <- Project.get(project_id),
         {app_name, module_name} = PluginScaffold.derive_names(project.title),
         plugin_dir = PluginScaffold.plugin_path(app_name),
         {:ok, _path} <- PluginScaffold.scaffold(app_name, module_name),
         {:ok, pipeline} <- from_project(project_id, tmux_session: session),
         {:ok, _report} <- validate_pipeline(pipeline.id),
         {:ok, pipeline_tasks} <- PipelineTask.by_run(pipeline.id),
         worker_groups = build_worker_groups(pipeline_tasks),
         prompt_ctx = %{plugin_dir: plugin_dir, module_name: module_name},
         spec =
           TeamSpec.build(
             :pipeline,
             pipeline,
             session,
             brief,
             pipeline_tasks,
             worker_groups,
             prompt_ctx
           ),
         {:ok, ^session} <- TeamLaunch.launch(spec) do
      Runner.start(:pipeline,
        run_id: pipeline.id,
        team_spec: spec,
        project_path: pipeline.project_path
      )

      Signals.emit(:pipeline_ready, %{
        run_id: pipeline.id,
        session: session,
        project_id: project_id,
        agent_count: length(spec.agents),
        worker_count: length(worker_groups)
      })

      {:ok, %{session: session, run: pipeline}}
    end
  end

  # ---------------------------------------------------------------------------
  # Planning spawn
  # ---------------------------------------------------------------------------

  @doc "Spawns a planning mode team (a/b/c) inside a new tmux session."
  @spec spawn(:planning, String.t(), String.t(), String.t() | nil) ::
          {:ok, String.t()} | {:error, term()}
  def spawn(:planning, mode, project_id, planning_project_id) do
    run_id = short_id()
    brief = load_project_brief(project_id)
    spec = TeamSpec.build(:planning, run_id, mode, project_id, planning_project_id, brief)

    case TeamLaunch.launch(spec) do
      {:ok, _session} ->
        Runner.start(:planning,
          run_id: run_id,
          mode: mode,
          team_spec: spec,
          project_id: planning_project_id
        )

        Signals.emit(:planning_team_ready, %{
          session: spec.session,
          mode: mode,
          project_id: project_id,
          agent_count: length(spec.agents)
        })

        {:ok, spec.session}

      {:error, reason} ->
        Signals.emit(:planning_team_spawn_failed, %{
          session: spec.session,
          reason: inspect(reason)
        })

        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Shared helpers (used by callers)
  # ---------------------------------------------------------------------------

  @doc "Returns the project ID to use for MES planning actions."
  @spec ensure_planning_project(String.t() | nil, map()) :: {:ok, String.t()} | {:error, term()}
  def ensure_planning_project(nil, project), do: {:ok, project.id}

  def ensure_planning_project(project_id, _project), do: {:ok, project_id}

  @doc "Loads a formatted brief artifact string for injection into agent prompts."
  @spec load_project_brief(String.t()) :: String.t()
  def load_project_brief(project_id) do
    case Project.get(project_id) do
      {:ok, project} ->
        Project.latest_brief_text(project) || render_project_fallback_brief(project)

      _ ->
        "BRIEF ARTIFACT: (not available)"
    end
  end

  # ---------------------------------------------------------------------------
  # Cleanup (formerly TeamCleanup)
  # ---------------------------------------------------------------------------

  @doc "Kills a MES tmux session and cleans up associated prompt files."
  @spec kill_session(String.t()) :: :ok
  def kill_session(session) do
    Signals.emit(:mes_team_killed, %{session: session})
    _ = cleanup_module().kill_session(session)
    cleanup_prompt_files(String.replace_prefix(session, "mes-", ""))
    :ok
  end

  @doc "Cleans up prompt directories and orphaned teams from previous runs."
  @spec cleanup_old_runs() :: :ok
  def cleanup_old_runs do
    cleanup_prompt_root_dir()
    cleanup_orphaned_teams()
    :ok
  end

  @doc "Removes all subdirectories under the MES prompt root directory."
  @spec cleanup_prompt_root_dir() :: :ok
  def cleanup_prompt_root_dir do
    case File.ls(TeamSpec.prompt_root_dir(:mes)) do
      {:ok, dirs} -> Enum.each(dirs, &remove_if_directory/1)
      {:error, _} -> :ok
    end

    :ok
  end

  @doc "Removes prompt files for a specific run ID."
  @spec cleanup_prompt_files(String.t()) :: :ok
  def cleanup_prompt_files(run_id) do
    dir = TeamSpec.prompt_dir(:mes, run_id)

    if File.dir?(dir) do
      cleanup_module().cleanup_prompt_dir(dir)
      Signals.emit(:mes_cleanup, %{target: "prompt_files/#{run_id}"})
    end

    :ok
  end

  @doc "Disbands fleet teams and kills tmux sessions not backed by an active Runner."
  @spec cleanup_orphaned_teams() :: :ok
  def cleanup_orphaned_teams do
    active_teams = active_team_names()
    orphaned_teams = orphaned_team_names(active_teams, team_entries())
    orphaned_sessions = orphaned_sessions(active_teams, tmux_launcher().list_sessions())

    cleanup_module().cleanup_orphaned_teams(active_teams, "mes-")
    cleanup_module().cleanup_orphaned_tmux_sessions(active_teams, "mes-")

    Enum.each(orphaned_teams, fn name ->
      Signals.emit(:mes_cleanup, %{target: "orphaned_team/#{name}"})
    end)

    Enum.each(orphaned_sessions, fn session ->
      Signals.emit(:mes_cleanup, %{target: "orphaned_tmux/#{session}"})
    end)

    :ok
  end

  @doc "Returns a MapSet of tmux session names for all active RunProcesses."
  @spec active_team_names() :: MapSet.t(String.t())
  def active_team_names do
    Runner.list_all(:mes)
    |> Enum.map(fn {run_id, _pid} -> TeamSpec.session_name(run_id) end)
    |> MapSet.new()
  end

  @doc "Returns team names from fleet entries that are not in the active set."
  @spec orphaned_team_names(MapSet.t(String.t()), [{String.t(), map()}]) :: [String.t()]
  def orphaned_team_names(active_teams, team_entries) do
    team_entries
    |> Enum.map(fn {name, _meta} -> name end)
    |> Enum.filter(&String.starts_with?(&1, "mes-"))
    |> Enum.reject(&MapSet.member?(active_teams, &1))
  end

  @doc "Returns tmux session names prefixed with `mes-` that are not in the active set."
  @spec orphaned_sessions(MapSet.t(String.t()), [String.t()]) :: [String.t()]
  def orphaned_sessions(active_teams, sessions) do
    sessions
    |> Enum.filter(&String.starts_with?(&1, "mes-"))
    |> Enum.reject(&MapSet.member?(active_teams, &1))
  end

  # ---------------------------------------------------------------------------
  # Loader (formerly Ichor.Projects.Loader)
  # ---------------------------------------------------------------------------

  @doc "Creates a pipeline and pipeline tasks from a tasks.jsonl file path."
  @spec from_file(String.t(), keyword()) :: {:ok, Pipeline.t()} | {:error, term()}
  def from_file(tasks_jsonl_path, opts \\ []) do
    label = Keyword.get(opts, :label, Path.basename(Path.dirname(tasks_jsonl_path)))
    tmux_session = Keyword.get(opts, :tmux_session)
    raw_items = parse_jsonl(tasks_jsonl_path)

    create_pipeline_with_tasks(raw_items, label, :imported, tmux_session, %{
      project_path: Path.dirname(tasks_jsonl_path)
    })
  end

  @doc "Creates a pipeline and pipeline tasks from a project roadmap hierarchy, archiving prior runs first."
  @spec from_project(String.t(), keyword()) :: {:ok, Pipeline.t()} | {:error, term()}
  def from_project(project_id, opts \\ []) do
    tmux_session = Keyword.get(opts, :tmux_session)
    archive_existing_runs_for_project(project_id)

    with {:ok, task_maps} <- PipelineCompiler.generate(project_id) do
      label = derive_label(project_id)
      raw_items = Enum.map(task_maps, &normalize_planning_map/1)

      create_pipeline_with_tasks(raw_items, label, :project, tmux_session, %{
        project_id: project_id
      })
    end
  end

  defp create_pipeline_with_tasks(raw_items, label, source, tmux_session, extra_attrs) do
    nodes = Enum.map(raw_items, &PipelineGraph.to_graph_node/1)
    waves = PipelineGraph.waves(nodes)
    wave_map = build_wave_map(waves)

    pipeline_attrs =
      Map.merge(extra_attrs, %{
        label: label,
        source: source,
        tmux_session: tmux_session
      })

    with {:ok, pipeline} <- Pipeline.create(pipeline_attrs),
         :ok <- create_pipeline_tasks(raw_items, pipeline.id, wave_map) do
      Signals.emit(:pipeline_created, %{
        run_id: pipeline.id,
        source: source,
        label: label,
        task_count: length(raw_items)
      })

      {:ok, pipeline}
    end
  end

  defp create_pipeline_tasks(raw_items, run_id, wave_map) do
    results = Enum.map(raw_items, &PipelineTask.create(to_task_attrs(&1, run_id, wave_map)))

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> :ok
      {:error, reason} -> {:error, {:pipeline_task_create_failed, reason}}
    end
  end

  defp to_task_attrs(item, run_id, wave_map) do
    %{
      run_id: run_id,
      external_id: item["id"],
      subtask_id: item["subtask_id"],
      subject: item["subject"],
      description: item["description"],
      goal: item["goal"],
      allowed_files: item["files"] || item["allowed_files"] || [],
      steps: item["steps"] || [],
      done_when: item["done_when"],
      blocked_by: item["blocked_by"] || [],
      priority: parse_priority(item["priority"]),
      wave: Map.get(wave_map, item["id"]),
      acceptance_criteria: item["acceptance_criteria"] || [],
      phase_label: item["feature"] || item["phase_label"],
      tags: item["tags"] || [],
      notes: item["notes"]
    }
  end

  defp normalize_planning_map(m), do: Map.put(m, "subtask_id", m["subtask_id"])

  defp parse_jsonl(path) do
    path
    |> File.stream!()
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn line ->
      case Jason.decode(line) do
        {:ok, map} -> map
        _ -> nil
      end
    end)
    |> Enum.reject(&(is_nil(&1) or &1["status"] == "deleted"))
  end

  defp build_wave_map(waves) do
    waves
    |> Enum.with_index()
    |> Enum.flat_map(fn {ids, wave_num} ->
      Enum.map(ids, &{&1, wave_num})
    end)
    |> Map.new()
  end

  defp parse_priority("critical"), do: :critical
  defp parse_priority("high"), do: :high
  defp parse_priority("medium"), do: :medium
  defp parse_priority("low"), do: :low
  defp parse_priority(_), do: :medium

  defp archive_existing_runs_for_project(project_id) do
    case Pipeline.by_project(project_id) do
      {:ok, pipelines} -> Enum.each(pipelines, &Pipeline.archive/1)
      _ -> :ok
    end
  end

  defp derive_label(project_id) do
    case Project.get(project_id) do
      {:ok, project} -> project.title
      _ -> "Pipeline"
    end
  end

  # ---------------------------------------------------------------------------
  # Validator (formerly Ichor.Projects.Validator)
  # ---------------------------------------------------------------------------

  defp validate_pipeline(run_id) do
    with {:ok, pipeline_tasks} <- PipelineTask.by_run(run_id) do
      items = Enum.map(pipeline_tasks, &PipelineGraph.to_graph_node/1)
      cycles = detect_cycles(items)
      missing = flat_pipeline_check(items)

      if cycles == [] and missing == [] do
        {:ok, %{cycles: [], missing_refs: []}}
      else
        {:error, %{cycles: cycles, missing_refs: missing}}
      end
    end
  end

  defp detect_cycles(items) do
    edges = for item <- items, dep <- item.blocked_by, do: {item.id, dep}

    for {a, b} <- edges,
        {^b, ^a} <- edges,
        a < b,
        do: {a, b}
  end

  defp flat_pipeline_check(items) do
    known_ids = MapSet.new(items, & &1.id)

    items
    |> Enum.map(fn %{id: id, blocked_by: deps} ->
      missing = Enum.reject(deps, &MapSet.member?(known_ids, &1))
      {id, missing}
    end)
    |> Enum.reject(fn {_id, missing} -> missing == [] end)
  end

  # ---------------------------------------------------------------------------
  # WorkerGroups (formerly Ichor.Projects.WorkerGroups)
  # ---------------------------------------------------------------------------

  defp build_worker_groups(jobs) do
    jobs
    |> Enum.sort_by(&{&1.wave || 0, &1.external_id})
    |> group_by_files()
    |> Enum.map(&enrich_group/1)
  end

  defp enrich_group(group) do
    %{
      name: group.name,
      capability: "builder",
      jobs: group.jobs,
      allowed_files: Enum.sort(group.files),
      waves: group.jobs |> Enum.map(&(&1.wave || 0)) |> Enum.uniq()
    }
  end

  defp group_by_files([]), do: []

  defp group_by_files(jobs) do
    jobs
    |> Enum.reduce([], &merge_into_groups/2)
    |> Enum.reverse()
    |> Enum.with_index(1)
    |> Enum.map(fn {group, idx} ->
      %{
        name: "worker-#{idx}",
        files: group.files,
        jobs: Enum.sort_by(group.jobs, & &1.wave)
      }
    end)
  end

  defp merge_into_groups(%{allowed_files: []} = job, groups) do
    [%{files: [], jobs: [job]} | groups]
  end

  defp merge_into_groups(job, groups) do
    file_set = MapSet.new(job.allowed_files)

    case find_overlap(file_set, groups) do
      {idx, existing} ->
        merged = %{
          files: Enum.uniq(existing.files ++ job.allowed_files),
          jobs: [job | existing.jobs]
        }

        List.replace_at(groups, idx, merged)

      nil ->
        [%{files: job.allowed_files, jobs: [job]} | groups]
    end
  end

  defp find_overlap(file_set, groups) do
    groups
    |> Enum.with_index()
    |> Enum.find_value(fn {group, idx} ->
      case MapSet.disjoint?(file_set, MapSet.new(group.files)) do
        false -> {idx, group}
        true -> nil
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Project brief fallback
  # ---------------------------------------------------------------------------

  defp render_project_fallback_brief(project) do
    """
    PROJECT BRIEF: #{project.title}
    Plugin: #{project.plugin}
    Description: #{project.description}
    Features: #{Enum.join(Project.artifact_titles(project, :feature), ", ")}
    Use Cases: #{Enum.join(Project.artifact_titles(project, :use_case), ", ")}
    Signal Interface: #{project.signal_interface}
    Signals Emitted: #{Enum.join(project.signals_emitted || [], ", ")}
    Signals Subscribed: #{Enum.join(project.signals_subscribed || [], ", ")}
    Architecture: #{project.architecture}
    Dependencies: #{Enum.join(project.dependencies || [], ", ")}
    """
  end

  # ---------------------------------------------------------------------------
  # Cleanup internals
  # ---------------------------------------------------------------------------

  defp remove_if_directory(dir) do
    path = Path.join(TeamSpec.prompt_root_dir(:mes), dir)

    if File.dir?(path) do
      cleanup_module().cleanup_prompt_dir(path)
      Signals.emit(:mes_cleanup, %{target: dir})
    end
  end

  defp team_entries do
    Application.get_env(:ichor, :mes_team_supervisor_module, Ichor.Infrastructure.TeamSupervisor).list_all()
  end

  defp cleanup_module do
    Application.get_env(:ichor, :mes_cleanup_module, Ichor.Infrastructure.Cleanup)
  end

  defp tmux_launcher do
    Application.get_env(:ichor, :mes_tmux_launcher_module, Ichor.Infrastructure.Tmux.Launcher)
  end

  defp short_id, do: :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
end
