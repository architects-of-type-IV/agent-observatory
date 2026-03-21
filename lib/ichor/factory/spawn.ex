defmodule Ichor.Factory.Spawn do
  @moduledoc """
  Spawns execution teams for pipeline and planning runs.

  Consolidates pipeline spawn (formerly Spawner) and planning mode spawn (formerly
  ModeSpawner) into a single module. Per-mode differences are expressed as
  data: session prefix, spec builder args, pre-launch steps.

  Delegates loading to Factory.Loader, validation to Factory.Validator,
  and worker group building to Factory.WorkerGroups.

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
    Loader,
    Pipeline,
    PipelineTask,
    Project,
    Runner,
    RunRef,
    Validator,
    WorkerGroups
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
    session = RunRef.new(:pipeline, short_id()) |> RunRef.session_name()
    brief = load_project_brief(project_id)

    with {:ok, project} <- Project.get(project_id),
         {app_name, module_name} = PluginScaffold.derive_names(project.title),
         plugin_dir = PluginScaffold.plugin_path(app_name),
         {:ok, _path} <- PluginScaffold.scaffold(app_name, module_name),
         {:ok, pipeline} <- from_project(project_id, tmux_session: session),
         {:ok, _report} <- Validator.validate_pipeline(pipeline.id),
         {:ok, pipeline_tasks} <- PipelineTask.by_run(pipeline.id),
         worker_groups = WorkerGroups.build(pipeline_tasks),
         prompt_ctx = %{plugin_dir: plugin_dir, module_name: module_name},
         spec =
           TeamSpec.build(
             :pipeline,
             pipeline,
             session,
             brief,
             pipeline_tasks,
             worker_groups,
             prompt_ctx,
             prompt_module: Ichor.Workshop.PipelinePrompts
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

    spec =
      TeamSpec.build(:planning, run_id, mode, project_id, planning_project_id, brief,
        prompt_module: Ichor.Factory.PlanningPrompts
      )

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

  @doc "Creates a pipeline and pipeline tasks from a tasks.jsonl file path."
  @spec from_file(String.t(), keyword()) :: {:ok, Pipeline.t()} | {:error, term()}
  defdelegate from_file(tasks_jsonl_path, opts \\ []), to: Loader

  @doc "Creates a pipeline and pipeline tasks from a project roadmap hierarchy."
  @spec from_project(String.t(), keyword()) :: {:ok, Pipeline.t()} | {:error, term()}
  defdelegate from_project(project_id, opts \\ []), to: Loader

  # ---------------------------------------------------------------------------
  # Cleanup (formerly TeamCleanup)
  # ---------------------------------------------------------------------------

  @doc "Kills a MES tmux session and cleans up associated prompt files."
  @spec kill_session(String.t()) :: :ok
  def kill_session(session) do
    Signals.emit(:mes_team_killed, %{session: session})
    _ = cleanup_module().kill_session(session)

    run_id =
      case RunRef.parse(session) do
        {:ok, %RunRef{run_id: id}} -> id
        :error -> session
      end

    cleanup_prompt_files(run_id)
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
    |> Enum.filter(&mes_session?/1)
    |> Enum.reject(&MapSet.member?(active_teams, &1))
  end

  @doc "Returns tmux session names prefixed with `mes-` that are not in the active set."
  @spec orphaned_sessions(MapSet.t(String.t()), [String.t()]) :: [String.t()]
  def orphaned_sessions(active_teams, sessions) do
    sessions
    |> Enum.filter(&mes_session?/1)
    |> Enum.reject(&MapSet.member?(active_teams, &1))
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

  defp mes_session?(name) do
    case RunRef.parse(name) do
      {:ok, %RunRef{kind: :mes}} -> true
      _ -> false
    end
  end

  defp short_id, do: :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
end
