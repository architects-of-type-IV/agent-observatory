defmodule Ichor.Archon.Manager do
  @moduledoc """
  Action-only Archon manager surface derived from the signal stream.
  """

  use Ash.Resource, domain: Ichor.Archon

  alias Ichor.Archon.SignalManager
  alias Ichor.Discovery

  actions do
    action :manager_snapshot, :map do
      description("Condensed managerial snapshot derived from Signals.")

      run(fn _input, _context ->
        snapshot = SignalManager.snapshot()
        attention = SignalManager.attention()
        {:ok, Map.put(snapshot, "attention", attention)}
      end)
    end

    action :attention_queue, {:array, :map} do
      description("Current high-signal issues that require Archon attention.")

      run(fn _input, _context ->
        {:ok, SignalManager.attention()}
      end)
    end

    action :discovery_catalog, {:array, :map} do
      description("Enumerate discoverable Ash workflow steps across all domains.")

      run(fn _input, _context ->
        {:ok, Discovery.available_steps()}
      end)
    end

    action :discovery_domain, {:array, :map} do
      description("Enumerate discoverable Ash workflow steps for a single domain.")
      argument(:domain, :string, allow_nil?: false)

      run(fn input, _context ->
        domain_name = input.arguments.domain

        case Discovery.domain(domain_name) do
          {:ok, domain} ->
            steps = Enum.filter(Discovery.available_steps(), &(&1.domain == domain.name))
            {:ok, steps}

          {:error, :unknown_domain} ->
            {:error, "unknown domain: #{domain_name}"}
        end
      end)
    end
  end
end
