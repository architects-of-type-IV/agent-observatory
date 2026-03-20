defmodule Ichor.Projects.Spawn do
  @moduledoc """
  Spawns execution teams for DAG and Genesis runs.

  Consolidates DAG spawn (formerly Spawner) and Genesis mode spawn (formerly
  ModeSpawner) into a single module. Per-mode differences are expressed as
  data: session prefix, spec builder args, pre-launch steps.

  Public API:
    - spawn(:dag, node_id, project_id)
    - spawn(:genesis, mode, project_id, genesis_node_id)
    - ensure_genesis_node(node_id_or_nil, project)
    - load_project_brief(project_id)
  """

  alias Ichor.Control.Lifecycle.TeamLaunch

  alias Ichor.Projects.Node, as: ProjectNode

  alias Ichor.Projects.{
    Graph,
    Job,
    Loader,
    Project,
    Runner,
    RuntimeSignals,
    TeamSpec,
    Validator,
    WorkerGroups
  }

  alias Ichor.Projects.SubsystemScaffold
  alias Ichor.Signals

  # ---------------------------------------------------------------------------
  # DAG spawn
  # ---------------------------------------------------------------------------

  @doc "Spawns a full DAG execution team for the given genesis node and project."
  @spec spawn(:dag, String.t(), String.t()) ::
          {:ok, %{session: String.t(), run: map()}} | {:error, term()}
  def spawn(:dag, node_id, project_id) do
    session = "dag-#{short_id()}"
    brief = load_project_brief(project_id)

    with {:ok, node} <- ProjectNode.get(node_id),
         {app_name, module_name} = SubsystemScaffold.derive_names(node.title),
         subsystem_dir = SubsystemScaffold.subsystem_path(app_name),
         {:ok, _path} <- SubsystemScaffold.scaffold(app_name, module_name),
         {:ok, run} <- Loader.from_genesis(node_id, tmux_session: session),
         {:ok, _report} <- validate_dag(run.id),
         {:ok, jobs} <- Job.by_run(run.id),
         worker_groups = build_worker_groups(jobs),
         prompt_ctx = %{subsystem_dir: subsystem_dir, module_name: module_name},
         spec = TeamSpec.build(:dag, run, session, brief, jobs, worker_groups, prompt_ctx),
         {:ok, ^session} <- TeamLaunch.launch(spec) do
      Runner.start(:dag, run_id: run.id, team_spec: spec, project_path: run.project_path)

      RuntimeSignals.emit_run_ready(
        run.id,
        session,
        node_id,
        length(spec.agents),
        length(worker_groups)
      )

      {:ok, %{session: session, run: run}}
    end
  end

  # ---------------------------------------------------------------------------
  # Genesis spawn
  # ---------------------------------------------------------------------------

  @doc "Spawns a Genesis mode team (a/b/c) inside a new tmux session."
  @spec spawn(:genesis, String.t(), String.t(), String.t() | nil) ::
          {:ok, String.t()} | {:error, term()}
  def spawn(:genesis, mode, project_id, genesis_node_id) do
    run_id = short_id()
    brief = load_project_brief(project_id)
    spec = TeamSpec.build(:genesis, run_id, mode, project_id, genesis_node_id, brief)

    case TeamLaunch.launch(spec) do
      {:ok, _session} ->
        Runner.start(:genesis,
          run_id: run_id,
          mode: mode,
          team_spec: spec,
          node_id: genesis_node_id
        )

        Signals.emit(:genesis_team_ready, %{
          session: spec.session,
          mode: mode,
          project_id: project_id,
          genesis_node_id: genesis_node_id,
          agent_count: length(spec.agents)
        })

        {:ok, spec.session}

      {:error, reason} ->
        Signals.emit(:genesis_team_spawn_failed, %{
          session: spec.session,
          reason: inspect(reason)
        })

        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Shared helpers (used by callers)
  # ---------------------------------------------------------------------------

  @doc "Returns an existing genesis node ID or creates one for the project."
  @spec ensure_genesis_node(String.t() | nil, map()) :: {:ok, String.t()} | {:error, term()}
  def ensure_genesis_node(nil, project) do
    case find_existing_node(project.id) do
      {:ok, node_id} -> {:ok, node_id}
      :not_found -> create_genesis_node(project)
    end
  end

  def ensure_genesis_node(node_id, _project), do: {:ok, node_id}

  @doc "Loads a formatted project brief string for injection into agent prompts."
  @spec load_project_brief(String.t()) :: String.t()
  def load_project_brief(project_id) do
    case Project.get(project_id) do
      {:ok, project} ->
        """
        PROJECT BRIEF: #{project.title}
        Subsystem: #{project.subsystem}
        Description: #{project.description}
        Features: #{Enum.join(project.features || [], ", ")}
        Use Cases: #{Enum.join(project.use_cases || [], ", ")}
        Signal Interface: #{project.signal_interface}
        Signals Emitted: #{Enum.join(project.signals_emitted || [], ", ")}
        Signals Subscribed: #{Enum.join(project.signals_subscribed || [], ", ")}
        Architecture: #{project.architecture}
        Dependencies: #{Enum.join(project.dependencies || [], ", ")}
        """

      _ ->
        "PROJECT BRIEF: (not available)"
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
  # DAG internals
  # ---------------------------------------------------------------------------

  defp build_worker_groups(jobs) do
    jobs
    |> Enum.sort_by(&{&1.wave || 0, &1.external_id})
    |> WorkerGroups.group()
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

  defp validate_dag(run_id) do
    with {:ok, jobs} <- Job.by_run(run_id) do
      items = Enum.map(jobs, &Graph.to_graph_node/1)
      cycles = Validator.detect_cycles(items)
      missing = Validator.flat_dag_check(items)

      if cycles == [] and missing == [] do
        {:ok, %{cycles: [], missing_refs: []}}
      else
        {:error, %{cycles: cycles, missing_refs: missing}}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Genesis internals
  # ---------------------------------------------------------------------------

  defp find_existing_node(project_id) do
    case ProjectNode.by_project(project_id) do
      {:ok, [node | _]} -> {:ok, node.id}
      _ -> :not_found
    end
  end

  defp create_genesis_node(project) do
    case ProjectNode.create(%{
           title: project.title,
           description: project.description,
           brief: project.description,
           mes_project_id: project.id
         }) do
      {:ok, node} -> {:ok, node.id}
      error -> error
    end
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
    Application.get_env(:ichor, :mes_team_supervisor_module, Ichor.Control.TeamSupervisor).list_all()
  end

  defp cleanup_module do
    Application.get_env(:ichor, :mes_cleanup_module, Ichor.Control.Lifecycle.Cleanup)
  end

  defp tmux_launcher do
    Application.get_env(:ichor, :mes_tmux_launcher_module, Ichor.Control.Lifecycle.TmuxLauncher)
  end

  defp short_id, do: :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
end
