defmodule Ichor.Projects.Types.ProjectStatus do
  @moduledoc """
  Ash enum type for MES project lifecycle status.

  - `:proposed`    -- brief submitted, not yet claimed
  - `:in_progress` -- an agent team is actively building it
  - `:compiled`    -- Mix project built and artifact written to disk
  - `:loaded`      -- BEAM modules live in the running VM
  - `:failed`      -- build or load failed; see build_log
  """

  use Ash.Type.Enum, values: [:proposed, :in_progress, :compiled, :loaded, :failed]
end
