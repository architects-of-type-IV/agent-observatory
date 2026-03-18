defmodule Ichor.Costs.CostAggregator do
  @moduledoc """
  Deprecated cost aggregation boundary.

  Costs are currently disabled, so this module intentionally behaves as a no-op
  and returns empty dashboard data.
  """

  @doc """
  Cost recording is disabled.
  """
  @spec record_usage(map(), map()) :: :ok
  def record_usage(_event, _raw), do: :ok

  @doc "Load aggregated cost data for the dashboard."
  @spec load_cost_data() :: map()
  def load_cost_data do
    %{
      by_model: by_model(),
      by_session: by_session(),
      totals: totals()
    }
  end

  defp by_model, do: []
  defp by_session, do: []
  defp totals, do: %{input_tokens: 0, output_tokens: 0, cache_read: 0, cost_cents: 0}
end
