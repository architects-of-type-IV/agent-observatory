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

  use Ash.Domain

  resources do
    resource(Ichor.Genesis.Node)
    resource(Ichor.Genesis.Adr)
    resource(Ichor.Genesis.Feature)
    resource(Ichor.Genesis.UseCase)
    resource(Ichor.Genesis.Checkpoint)
    resource(Ichor.Genesis.Conversation)
    resource(Ichor.Genesis.Phase)
    resource(Ichor.Genesis.Section)
    resource(Ichor.Genesis.Task)
    resource(Ichor.Genesis.Subtask)
  end

  @spec get_node(String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def get_node(id, opts \\ []) do
    Ichor.Genesis.Node.get(id, opts)
  end

  @spec node_by_project(String.t(), keyword()) :: {:ok, list(term())} | {:error, term()}
  def node_by_project(project_id, opts \\ []) do
    Ichor.Genesis.Node.by_project(project_id, opts)
  end
end
