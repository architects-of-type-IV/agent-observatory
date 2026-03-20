defmodule Ichor.Archon.Manager do
  @moduledoc """
  Action-only Archon manager surface derived from the signal stream.
  """

  use Ash.Resource, domain: Ichor.Archon

  alias Ichor.Archon.SignalManager

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
  end
end
