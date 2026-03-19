defmodule Ichor.Projects.Job.Preparations.FilterAvailable do
  @moduledoc """
  Post-query filter for the :available read action.
  Removes jobs whose blocked_by dependencies are not all completed.

  Two-query pattern: SQLite cannot filter JSON arrays via Ash expressions.
  1. The action's SQL filter handles: status == :pending AND owner IS NULL
  2. This prepare loads completed external_ids and filters in Elixir
  """

  use Ash.Resource.Preparation

  alias Ichor.Projects.Job

  @impl true
  def prepare(query, _opts, _context) do
    Ash.Query.after_action(query, fn _query, results ->
      run_id = Ash.Query.get_argument(query, :run_id)
      completed_ids = completed_external_ids(run_id)

      available =
        Enum.filter(results, fn job ->
          Enum.all?(job.blocked_by, &MapSet.member?(completed_ids, &1))
        end)

      {:ok, available}
    end)
  end

  defp completed_external_ids(run_id) do
    case Job.by_run(run_id) do
      {:ok, jobs} ->
        jobs
        |> Enum.filter(&(&1.status == :completed))
        |> MapSet.new(& &1.external_id)

      _ ->
        MapSet.new()
    end
  end
end
