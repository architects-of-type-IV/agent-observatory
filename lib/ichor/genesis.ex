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
end
