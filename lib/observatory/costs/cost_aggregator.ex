defmodule Observatory.Costs.CostAggregator do
  @moduledoc """
  Aggregates token usage data for the cost dashboard.

  Queries the TokenUsage SQLite table and groups by model and session.
  Called from DashboardState.recompute/1.
  """

  alias Observatory.Repo

  @doc "Load aggregated cost data for the dashboard."
  @spec load_cost_data() :: map()
  def load_cost_data do
    %{
      by_model: by_model(),
      by_session: by_session(),
      totals: totals()
    }
  end

  defp by_model do
    query = """
    SELECT
      model_name,
      SUM(input_tokens) as input_tokens,
      SUM(output_tokens) as output_tokens,
      SUM(cache_read_tokens) as cache_read_tokens,
      SUM(estimated_cost_cents) as cost_cents,
      COUNT(*) as count
    FROM token_usages
    GROUP BY model_name
    ORDER BY cost_cents DESC
    """

    case Repo.query(query) do
      {:ok, %{rows: rows, columns: columns}} ->
        Enum.map(rows, fn row ->
          map = Enum.zip(columns, row) |> Map.new()

          %{
            model: map["model_name"],
            input_tokens: map["input_tokens"] || 0,
            output_tokens: map["output_tokens"] || 0,
            cache_read_tokens: map["cache_read_tokens"] || 0,
            cost_cents: map["cost_cents"] || 0,
            count: map["count"] || 0
          }
        end)

      _ ->
        []
    end
  end

  defp by_session do
    query = """
    SELECT
      session_id,
      source_app,
      model_name,
      SUM(input_tokens) as input_tokens,
      SUM(output_tokens) as output_tokens,
      SUM(estimated_cost_cents) as cost_cents,
      COUNT(*) as count
    FROM token_usages
    GROUP BY session_id
    ORDER BY cost_cents DESC
    LIMIT 50
    """

    case Repo.query(query) do
      {:ok, %{rows: rows, columns: columns}} ->
        Enum.map(rows, fn row ->
          map = Enum.zip(columns, row) |> Map.new()
          sid = map["session_id"] || ""

          %{
            session_id: sid,
            label: map["source_app"] || String.slice(sid, 0, 8),
            model: map["model_name"],
            input_tokens: map["input_tokens"] || 0,
            output_tokens: map["output_tokens"] || 0,
            cost_cents: map["cost_cents"] || 0,
            count: map["count"] || 0
          }
        end)

      _ ->
        []
    end
  end

  defp totals do
    query = """
    SELECT
      COALESCE(SUM(input_tokens), 0) as input_tokens,
      COALESCE(SUM(output_tokens), 0) as output_tokens,
      COALESCE(SUM(cache_read_tokens), 0) as cache_read,
      COALESCE(SUM(estimated_cost_cents), 0) as cost_cents
    FROM token_usages
    """

    case Repo.query(query) do
      {:ok, %{rows: [row], columns: columns}} ->
        map = Enum.zip(columns, row) |> Map.new()

        %{
          input_tokens: map["input_tokens"] || 0,
          output_tokens: map["output_tokens"] || 0,
          cache_read: map["cache_read"] || 0,
          cost_cents: map["cost_cents"] || 0
        }

      _ ->
        %{input_tokens: 0, output_tokens: 0, cache_read: 0, cost_cents: 0}
    end
  end
end
