defmodule Ichor.Genesis do
  @moduledoc """
  Ash Domain: Genesis Nodes.

  Monad Method pipeline for turning MES subsystem proposals into
  fully planned, DAG-ready executable projects.

  Pipeline: MES brief (proposed) -> Mode A (ADRs) -> Mode B (FRDs/UCs)
  -> Mode C (roadmap) -> DAG execution.

  Self-contained in Ichor's SQLite. Mirrors the Genesis app schema
  for future sync but operates standalone.
  """

  use Ash.Domain, validate_config_inclusion?: false

  alias Ichor.Genesis.{
    Adr,
    Checkpoint,
    Conversation,
    Feature,
    Node,
    Phase,
    Section,
    Subtask,
    Task,
    UseCase
  }

  resources do
    resource(Node)
    resource(Adr)
    resource(Feature)
    resource(UseCase)
    resource(Checkpoint)
    resource(Conversation)
    resource(Phase)
    resource(Section)
    resource(Task)
    resource(Subtask)
  end

  @spec get_node(String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def get_node(id, opts \\ []) do
    Node.get(id, opts)
  end

  @spec node_by_project(String.t(), keyword()) :: {:ok, list(term())} | {:error, term()}
  def node_by_project(project_id, opts \\ []) do
    Node.by_project(project_id, opts)
  end

  @spec create_node(map()) :: {:ok, Node.t()} | {:error, term()}
  def create_node(attrs) do
    Node.create(attrs)
  end

  @spec advance_node(String.t(), atom()) :: {:ok, Node.t()} | {:error, term()}
  def advance_node(node_id, status) do
    with {:ok, node} <- Node.get(node_id) do
      Node.advance(node, status)
    end
  end

  @spec list_nodes() :: {:ok, list(Node.t())} | {:error, term()}
  def list_nodes do
    Node.list_all()
  end

  @spec load_node(String.t(), list()) :: {:ok, term()} | {:error, term()}
  def load_node(node_id, loads) do
    with {:ok, node} <- Node.get(node_id) do
      Ash.load(node, loads)
    end
  end

  # ADR

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

  # Feature

  @doc "Create a Feature Requirements Document."
  @spec create_feature(map()) :: {:ok, Feature.t()} | {:error, term()}
  def create_feature(attrs), do: Feature.create(attrs)

  @doc "Fetch a Feature by id."
  @spec get_feature(String.t()) :: {:ok, Feature.t()} | {:error, term()}
  def get_feature(id), do: Feature.get(id)

  @doc "List all Features for a node."
  @spec features_by_node(String.t()) :: {:ok, list(Feature.t())} | {:error, term()}
  def features_by_node(node_id), do: Feature.by_node(node_id)

  # UseCase

  @doc "Create a Use Case."
  @spec create_use_case(map()) :: {:ok, UseCase.t()} | {:error, term()}
  def create_use_case(attrs), do: UseCase.create(attrs)

  @doc "Fetch a UseCase by id."
  @spec get_use_case(String.t()) :: {:ok, UseCase.t()} | {:error, term()}
  def get_use_case(id), do: UseCase.get(id)

  @doc "List all Use Cases for a node."
  @spec use_cases_by_node(String.t()) :: {:ok, list(UseCase.t())} | {:error, term()}
  def use_cases_by_node(node_id), do: UseCase.by_node(node_id)

  # Checkpoint

  @doc "Create a gate Checkpoint."
  @spec create_checkpoint(map()) :: {:ok, Checkpoint.t()} | {:error, term()}
  def create_checkpoint(attrs), do: Checkpoint.create(attrs)

  @doc "Fetch a Checkpoint by id."
  @spec get_checkpoint(String.t()) :: {:ok, Checkpoint.t()} | {:error, term()}
  def get_checkpoint(id), do: Checkpoint.get(id)

  @doc "List all Checkpoints for a node."
  @spec checkpoints_by_node(String.t()) :: {:ok, list(Checkpoint.t())} | {:error, term()}
  def checkpoints_by_node(node_id), do: Checkpoint.by_node(node_id)

  # Conversation

  @doc "Create a design Conversation log."
  @spec create_conversation(map()) :: {:ok, Conversation.t()} | {:error, term()}
  def create_conversation(attrs), do: Conversation.create(attrs)

  @doc "Fetch a Conversation by id."
  @spec get_conversation(String.t()) :: {:ok, Conversation.t()} | {:error, term()}
  def get_conversation(id), do: Conversation.get(id)

  @doc "List all Conversations for a node."
  @spec conversations_by_node(String.t()) :: {:ok, list(Conversation.t())} | {:error, term()}
  def conversations_by_node(node_id), do: Conversation.by_node(node_id)

  # Phase

  @doc "Create a roadmap Phase."
  @spec create_phase(map()) :: {:ok, Phase.t()} | {:error, term()}
  def create_phase(attrs), do: Phase.create(attrs)

  @doc "Fetch a Phase by id."
  @spec get_phase(String.t()) :: {:ok, Phase.t()} | {:error, term()}
  def get_phase(id), do: Phase.get(id)

  @doc "List all Phases for a node."
  @spec phases_by_node(String.t()) :: {:ok, list(Phase.t())} | {:error, term()}
  def phases_by_node(node_id), do: Phase.by_node(node_id)

  # Section

  @doc "Create a Section within a Phase."
  @spec create_section(map()) :: {:ok, Section.t()} | {:error, term()}
  def create_section(attrs), do: Section.create(attrs)

  @doc "Fetch a Section by id."
  @spec get_section(String.t()) :: {:ok, Section.t()} | {:error, term()}
  def get_section(id), do: Section.get(id)

  @doc "List all Sections for a phase."
  @spec sections_by_phase(String.t()) :: {:ok, list(Section.t())} | {:error, term()}
  def sections_by_phase(phase_id), do: Section.by_phase(phase_id)

  # Task

  @doc "Create a Task within a Section."
  @spec create_task(map()) :: {:ok, Task.t()} | {:error, term()}
  def create_task(attrs), do: Task.create(attrs)

  @doc "Fetch a Task by id."
  @spec get_task(String.t()) :: {:ok, Task.t()} | {:error, term()}
  def get_task(id), do: Task.get(id)

  @doc "List all Tasks for a section."
  @spec tasks_by_section(String.t()) :: {:ok, list(Task.t())} | {:error, term()}
  def tasks_by_section(section_id), do: Task.by_section(section_id)

  # Subtask

  @doc "Create a Subtask within a Task."
  @spec create_subtask(map()) :: {:ok, Subtask.t()} | {:error, term()}
  def create_subtask(attrs), do: Subtask.create(attrs)

  @doc "Fetch a Subtask by id."
  @spec get_subtask(String.t()) :: {:ok, Subtask.t()} | {:error, term()}
  def get_subtask(id), do: Subtask.get(id)

  @doc "List all Subtasks for a task."
  @spec subtasks_by_task(String.t()) :: {:ok, list(Subtask.t())} | {:error, term()}
  def subtasks_by_task(task_id), do: Subtask.by_task(task_id)
end
