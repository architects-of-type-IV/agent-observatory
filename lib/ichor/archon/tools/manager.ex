defmodule Ichor.Archon.Tools.Manager do
  @moduledoc """
  Manager-facing signal summaries for Archon.
  """

  use Ash.Resource, domain: Ichor.Tools

  alias Ichor.Archon.SignalManager

  actions do
    action :manager_snapshot, :map do
      description("Condensed managerial snapshot derived from Signals.")

      run(fn _input, _context ->
        {:ok, SignalManager.snapshot()}
      end)
    end

    action :attention_queue, {:array, :map} do
      description("Current high-signal issues Archon should pay attention to.")

      run(fn _input, _context ->
        {:ok, SignalManager.attention()}
      end)
    end
  end
end
