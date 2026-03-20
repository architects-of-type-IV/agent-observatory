defmodule Ichor.Archon do
  @moduledoc """
  Ash Domain: Archon-only manager and memory surfaces.
  """

  use Ash.Domain, extensions: [AshAi]

  resources do
    resource(Ichor.Archon.Memory)
    resource(Ichor.Archon.Manager)
  end

  tools do
    tool(:manager_snapshot, Ichor.Archon.Manager, :manager_snapshot)
    tool(:attention_queue, Ichor.Archon.Manager, :attention_queue)
    tool(:discovery_catalog, Ichor.Archon.Manager, :discovery_catalog)
    tool(:discovery_domain, Ichor.Archon.Manager, :discovery_domain)
    tool(:search_memory, Ichor.Archon.Memory, :search_memory)
    tool(:remember, Ichor.Archon.Memory, :remember)
    tool(:query_memory, Ichor.Archon.Memory, :query_memory)
  end
end
