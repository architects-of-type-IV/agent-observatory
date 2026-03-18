defmodule Ichor.Dag do
  @moduledoc """
  Ash Domain: DAG Execution.

  Sovereign task execution control plane. Manages parallel agent work
  through directed acyclic graphs of claimable jobs with dependency chains.

  Separate from Genesis (planning) -- they relate via node_id but are
  independent bounded contexts.
  """

  use Ash.Domain

  resources do
    resource(Ichor.Dag.Run)
    resource(Ichor.Dag.Job)
  end
end
