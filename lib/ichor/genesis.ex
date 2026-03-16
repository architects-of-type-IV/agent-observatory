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
  end
end
