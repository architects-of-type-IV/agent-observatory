defmodule Mix.Tasks.Ichor.BoundaryAudit do
  @shortdoc "Audit host-app de-umbrella boundary violations"

  @moduledoc """
  Runs a non-mutating audit over the main app source tree to surface:

  - direct `Ash.*` usage
  - direct resource-module references from host code
  - legacy `swarm_*` terminology

  Usage:

      mix ichor.boundary_audit
      mix ichor.boundary_audit --strict
  """

  use Mix.Task

  @impl true
  def run(args) do
    {opts, _argv, _invalid} = OptionParser.parse(args, strict: [strict: :boolean])

    report = Ichor.Architecture.BoundaryAudit.run()

    Ichor.Architecture.BoundaryAudit.print_report(report,
      strict: Keyword.get(opts, :strict, false)
    )
  end
end
