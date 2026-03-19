defmodule Ichor.Projects do
  @moduledoc """
  Ash Domain: Project lifecycle from planning through execution.

  Genesis is planning. DAG resolves dependencies into execution waves.
  MES is the project lifecycle container. A swarm is coordinated agents
  executing wave-ready tasks.
  """
  use Ash.Domain

  alias Ichor.Projects.{
    Adr,
    Checkpoint,
    Conversation,
    Feature,
    Job,
    Node,
    Phase,
    Project,
    RoadmapTask,
    Run,
    Section,
    Subtask,
    UseCase
  }

  resources do
    resource(Ichor.Projects.Project)
    resource(Ichor.Projects.Node)
    resource(Ichor.Projects.Adr)
    resource(Ichor.Projects.Feature)
    resource(Ichor.Projects.UseCase)
    resource(Ichor.Projects.Checkpoint)
    resource(Ichor.Projects.Conversation)
    resource(Ichor.Projects.Phase)
    resource(Ichor.Projects.Section)
    resource(Ichor.Projects.RoadmapTask)
    resource(Ichor.Projects.Subtask)
    resource(Ichor.Projects.Run)
    resource(Ichor.Projects.Job)
  end

  # Project Intake

  @doc "Fetch a single project by id."
  @spec get_project(String.t()) :: {:ok, Project.t()} | {:error, term()}
  def get_project(id), do: Project.get(id)

  @doc "Create a new project from the given attrs map."
  @spec create_project(map()) :: {:ok, Project.t()} | {:error, term()}
  def create_project(attrs), do: Project.create(attrs)

  @doc "Return all projects, raising on error."
  @spec list_projects() :: list(Project.t())
  def list_projects, do: Project.list_all!()

  @doc "Return all projects with :loaded status, returning an empty list on error."
  @spec loaded_projects() :: list(Project.t())
  def loaded_projects do
    case Project.by_status(:loaded) do
      {:ok, projects} -> projects
      _ -> []
    end
  end

  @doc "Return all projects, returning an empty list on error."
  @spec all_projects() :: list(Project.t())
  def all_projects do
    case Project.list_all() do
      {:ok, projects} -> projects
      _ -> []
    end
  end

  @doc "Transition a project to :loaded status."
  @spec mark_loaded(Project.t()) :: {:ok, Project.t()} | {:error, term()}
  def mark_loaded(project), do: Project.mark_loaded(project)

  @doc "Transition a project to :failed status with the given build log."
  @spec mark_failed(Project.t(), String.t()) :: {:ok, Project.t()} | {:error, term()}
  def mark_failed(project, build_log), do: Project.mark_failed(project, build_log)

  @doc "Claim a project for implementation by the given session."
  @spec pick_up_project(Project.t(), String.t()) :: {:ok, Project.t()} | {:error, term()}
  def pick_up_project(project, session_id), do: Project.pick_up(project, session_id)

  @doc "List all projects matching the given status atom."
  @spec projects_by_status(atom()) :: list(Project.t())
  def projects_by_status(status) do
    case Project.by_status(status) do
      {:ok, projects} -> projects
      _ -> []
    end
  end

  @doc "List all projects matching the given status atom, raising on error."
  @spec projects_by_status!(atom()) :: list(Project.t())
  def projects_by_status!(status), do: Project.by_status!(status)

  # Planning Nodes

  @doc "Fetch a single genesis node by id, with optional load opts."
  @spec get_node(String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def get_node(id, opts \\ []) do
    Node.get(id, opts)
  end

  @doc "Return all genesis nodes for the given project id."
  @spec node_by_project(String.t(), keyword()) :: {:ok, list(term())} | {:error, term()}
  def node_by_project(project_id, opts \\ []) do
    Node.by_project(project_id, opts)
  end

  @doc "Create a new genesis node from the given attrs map."
  @spec create_node(map()) :: {:ok, Node.t()} | {:error, term()}
  def create_node(attrs) do
    Node.create(attrs)
  end

  @doc "Advance a genesis node to the given status atom."
  @spec advance_node(String.t(), atom()) :: {:ok, Node.t()} | {:error, term()}
  def advance_node(node_id, status) do
    with {:ok, node} <- Node.get(node_id) do
      Node.advance(node, status)
    end
  end

  @doc "Return all genesis nodes."
  @spec list_nodes() :: {:ok, list(Node.t())} | {:error, term()}
  def list_nodes do
    Node.list_all()
  end

  @doc "Load the given relationships onto a node by id."
  @spec load_node(String.t(), list()) :: {:ok, term()} | {:error, term()}
  def load_node(node_id, loads) do
    with {:ok, node} <- Node.get(node_id) do
      Ash.load(node, loads)
    end
  end

  # Design Artifacts

  @doc "Create an Architecture Decision Record."
  @spec create_adr(map()) :: {:ok, Adr.t()} | {:error, term()}
  def create_adr(attrs), do: Adr.create(attrs)

  @doc "Fetch an ADR by id."
  @spec get_adr(String.t()) :: {:ok, Adr.t()} | {:error, term()}
  def get_adr(id), do: Adr.get(id)

  @doc "Update an existing ADR."
  @spec update_adr(Adr.t(), map()) :: {:ok, Adr.t()} | {:error, term()}
  def update_adr(adr, attrs), do: Adr.update(adr, attrs)

  @doc "List all ADRs for a node."
  @spec adrs_by_node(String.t()) :: {:ok, list(Adr.t())} | {:error, term()}
  def adrs_by_node(node_id), do: Adr.by_node(node_id)

  @doc "Create a Feature Requirements Document."
  @spec create_feature(map()) :: {:ok, Feature.t()} | {:error, term()}
  def create_feature(attrs), do: Feature.create(attrs)

  @doc "Fetch a Feature by id."
  @spec get_feature(String.t()) :: {:ok, Feature.t()} | {:error, term()}
  def get_feature(id), do: Feature.get(id)

  @doc "List all Features for a node."
  @spec features_by_node(String.t()) :: {:ok, list(Feature.t())} | {:error, term()}
  def features_by_node(node_id), do: Feature.by_node(node_id)

  @doc "Create a Use Case."
  @spec create_use_case(map()) :: {:ok, UseCase.t()} | {:error, term()}
  def create_use_case(attrs), do: UseCase.create(attrs)

  @doc "Fetch a UseCase by id."
  @spec get_use_case(String.t()) :: {:ok, UseCase.t()} | {:error, term()}
  def get_use_case(id), do: UseCase.get(id)

  @doc "List all Use Cases for a node."
  @spec use_cases_by_node(String.t()) :: {:ok, list(UseCase.t())} | {:error, term()}
  def use_cases_by_node(node_id), do: UseCase.by_node(node_id)

  @doc "Create a gate Checkpoint."
  @spec create_checkpoint(map()) :: {:ok, Checkpoint.t()} | {:error, term()}
  def create_checkpoint(attrs), do: Checkpoint.create(attrs)

  @doc "Fetch a Checkpoint by id."
  @spec get_checkpoint(String.t()) :: {:ok, Checkpoint.t()} | {:error, term()}
  def get_checkpoint(id), do: Checkpoint.get(id)

  @doc "List all Checkpoints for a node."
  @spec checkpoints_by_node(String.t()) :: {:ok, list(Checkpoint.t())} | {:error, term()}
  def checkpoints_by_node(node_id), do: Checkpoint.by_node(node_id)

  @doc "Create a design Conversation log."
  @spec create_conversation(map()) :: {:ok, Conversation.t()} | {:error, term()}
  def create_conversation(attrs), do: Conversation.create(attrs)

  @doc "Fetch a Conversation by id."
  @spec get_conversation(String.t()) :: {:ok, Conversation.t()} | {:error, term()}
  def get_conversation(id), do: Conversation.get(id)

  @doc "List all Conversations for a node."
  @spec conversations_by_node(String.t()) :: {:ok, list(Conversation.t())} | {:error, term()}
  def conversations_by_node(node_id), do: Conversation.by_node(node_id)

  # Roadmap Hierarchy

  @doc "Create a roadmap Phase."
  @spec create_phase(map()) :: {:ok, Phase.t()} | {:error, term()}
  def create_phase(attrs), do: Phase.create(attrs)

  @doc "Fetch a Phase by id."
  @spec get_phase(String.t()) :: {:ok, Phase.t()} | {:error, term()}
  def get_phase(id), do: Phase.get(id)

  @doc "List all Phases for a node."
  @spec phases_by_node(String.t()) :: {:ok, list(Phase.t())} | {:error, term()}
  def phases_by_node(node_id), do: Phase.by_node(node_id)

  @doc "Create a Section within a Phase."
  @spec create_section(map()) :: {:ok, Section.t()} | {:error, term()}
  def create_section(attrs), do: Section.create(attrs)

  @doc "Fetch a Section by id."
  @spec get_section(String.t()) :: {:ok, Section.t()} | {:error, term()}
  def get_section(id), do: Section.get(id)

  @doc "List all Sections for a phase."
  @spec sections_by_phase(String.t()) :: {:ok, list(Section.t())} | {:error, term()}
  def sections_by_phase(phase_id), do: Section.by_phase(phase_id)

  @doc "Create a Task within a Section."
  @spec create_task(map()) :: {:ok, RoadmapTask.t()} | {:error, term()}
  def create_task(attrs), do: RoadmapTask.create(attrs)

  @doc "Fetch a Task by id."
  @spec get_task(String.t()) :: {:ok, RoadmapTask.t()} | {:error, term()}
  def get_task(id), do: RoadmapTask.get(id)

  @doc "List all Tasks for a section."
  @spec tasks_by_section(String.t()) :: {:ok, list(RoadmapTask.t())} | {:error, term()}
  def tasks_by_section(section_id), do: RoadmapTask.by_section(section_id)

  @doc "Create a Subtask within a Task."
  @spec create_subtask(map()) :: {:ok, Subtask.t()} | {:error, term()}
  def create_subtask(attrs), do: Subtask.create(attrs)

  @doc "Fetch a Subtask by id."
  @spec get_subtask(String.t()) :: {:ok, Subtask.t()} | {:error, term()}
  def get_subtask(id), do: Subtask.get(id)

  @doc "List all Subtasks for a task."
  @spec subtasks_by_task(String.t()) :: {:ok, list(Subtask.t())} | {:error, term()}
  def subtasks_by_task(task_id), do: Subtask.by_task(task_id)

  # Execution

  @doc "Fetch a single DAG run by id."
  @spec get_run(String.t()) :: {:ok, Run.t()} | {:error, term()}
  def get_run(id), do: Run.get(id)

  @doc "Return all active DAG runs, raising on error."
  @spec active_runs() :: list(Run.t())
  def active_runs, do: Run.active!()

  @doc "Return all DAG runs for the given genesis node id, raising on error."
  @spec runs_by_node(String.t()) :: list(Run.t())
  def runs_by_node(node_id), do: Run.by_node!(node_id)

  @doc "Return all DAG runs for the given project path, raising on error."
  @spec runs_by_path(String.t()) :: list(Run.t())
  def runs_by_path(project_path), do: Run.by_path!(project_path)

  @doc "Return all jobs for the given run id, raising on error."
  @spec jobs_for_run(String.t()) :: list(Job.t())
  def jobs_for_run(run_id), do: Job.by_run!(run_id)

  @doc "Return all jobs for the given run id, returning a tagged tuple."
  @spec fetch_jobs_for_run(String.t()) :: {:ok, list(Job.t())} | {:error, term()}
  def fetch_jobs_for_run(run_id), do: Job.by_run(run_id)
end
