defmodule Ichor.Projects.Catalog do
  @moduledoc """
  Project selection, discovery, and tasks-path helpers for the DAG runtime.
  """

  alias Ichor.Projects.Discovery

  @doc "Builds the initial project state map from discovered projects."
  @spec initial_state() :: map()
  def initial_state do
    projects = Discovery.discover_projects()

    %{
      watched_projects: projects,
      manual_projects: %{},
      active_project: first_project_key(projects),
      known_cwds: MapSet.new(),
      archives: Discovery.scan_archives()
    }
  end

  @doc "Sets the active project by key, returning an error if not found."
  @spec set_active_project(map(), String.t()) :: {:ok, map()} | {:error, :unknown_project}
  def set_active_project(state, key) do
    if Map.has_key?(state.watched_projects, key) do
      {:ok, %{state | active_project: key}}
    else
      {:error, :unknown_project}
    end
  end

  @doc "Adds a project at path under key, activating it immediately."
  @spec add_project(map(), String.t(), String.t()) :: {:ok, map()} | {:error, :path_not_found}
  def add_project(state, key, path) do
    tasks_path = Path.join(path, "tasks.jsonl")

    if File.exists?(tasks_path) or File.dir?(path) do
      manual = Map.put(state.manual_projects, key, path)
      projects = Map.put(state.watched_projects, key, path)

      {:ok, %{state | manual_projects: manual, watched_projects: projects, active_project: key}}
    else
      {:error, :path_not_found}
    end
  end

  @doc "Re-discovers projects and merges with manual entries. Returns `{state, changed?}`."
  @spec refresh_discovered_projects(map()) :: {map(), boolean()}
  def refresh_discovered_projects(state) do
    new_projects = Map.merge(Discovery.discover_projects(), state.manual_projects)

    if new_projects != state.watched_projects do
      active =
        if state.active_project && Map.has_key?(new_projects, state.active_project),
          do: state.active_project,
          else: first_project_key(new_projects)

      {%{state | watched_projects: new_projects, active_project: active}, true}
    else
      {state, false}
    end
  end

  @doc "Registers a working directory as a watched project if it contains tasks.jsonl."
  @spec register_cwd(map(), String.t()) :: {map(), boolean()}
  def register_cwd(state, cwd) when is_binary(cwd) and cwd != "" do
    if MapSet.member?(state.known_cwds, cwd) do
      {state, false}
    else
      new_cwds = MapSet.put(state.known_cwds, cwd)
      key = Path.basename(cwd)
      tasks_path = Path.join(cwd, "tasks.jsonl")

      if File.exists?(tasks_path) and not Map.has_key?(state.watched_projects, key) do
        projects = Map.put(state.watched_projects, key, cwd)
        active = state.active_project || key

        {%{state | watched_projects: projects, active_project: active, known_cwds: new_cwds},
         true}
      else
        {%{state | known_cwds: new_cwds}, false}
      end
    end
  end

  def register_cwd(state, _cwd), do: {state, false}

  @doc "Returns the tasks.jsonl path for the active project, or nil if none."
  @spec tasks_jsonl_path(map()) :: String.t() | nil
  def tasks_jsonl_path(state) do
    case active_project_path(state) do
      nil -> nil
      path -> Path.join(path, "tasks.jsonl")
    end
  end

  @doc "Returns the tasks.jsonl path for the project that owns the given task."
  @spec tasks_jsonl_path_for_task(map(), String.t()) :: String.t() | nil
  def tasks_jsonl_path_for_task(state, task_id) do
    case Enum.find(state.tasks, fn task -> task.id == task_id end) do
      nil ->
        tasks_jsonl_path(state)

      %{project: project} when project != "" ->
        case Map.get(state.watched_projects, project) do
          nil -> tasks_jsonl_path(state)
          path -> Path.join(path, "tasks.jsonl")
        end

      _ ->
        tasks_jsonl_path(state)
    end
  end

  @doc "Returns the filesystem path for the active project, or nil."
  @spec active_project_path(map()) :: String.t() | nil
  def active_project_path(state) do
    case state.active_project do
      nil -> nil
      key -> Map.get(state.watched_projects, key)
    end
  end

  @doc "Returns the first project key from the map, or nil if empty."
  @spec first_project_key(map()) :: String.t() | nil
  def first_project_key(projects) when map_size(projects) == 0, do: nil
  def first_project_key(projects), do: projects |> Map.keys() |> hd()
end
