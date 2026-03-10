defmodule Ichor.Costs.CostAggregator do
  @moduledoc """
  Aggregates token usage data for the cost dashboard.

  Queries the TokenUsage SQLite table and groups by model and session.
  Called from DashboardState.recompute/1.
  """

  require Logger

  alias Ichor.Gateway.AgentRegistry.AgentEntry
  alias Ichor.Repo

  @doc """
  Record token usage from a hook event's raw payload.
  Runs async to avoid blocking the event pipeline.
  """
  @spec record_usage(map(), map()) :: :ok
  def record_usage(event, raw) when is_map(raw) do
    input_tokens = usage_field(raw, "input_tokens")
    output_tokens = usage_field(raw, "output_tokens")

    if input_tokens > 0 or output_tokens > 0 do
      cache_read = usage_field(raw, "cache_read_input_tokens")
      cache_write = usage_field(raw, "cache_creation_input_tokens")
      cost_cents = estimate_cost_cents(event.model_name, input_tokens, output_tokens, cache_read)

      attrs = %{
        session_id: event.session_id,
        source_app: event.source_app,
        model_name: event.model_name || "unknown",
        input_tokens: input_tokens,
        output_tokens: output_tokens,
        cache_read_tokens: cache_read,
        cache_write_tokens: cache_write,
        estimated_cost_cents: cost_cents,
        tool_name: event.tool_name
      }

      Task.start(fn ->
        try do
          Ichor.Costs.TokenUsage
          |> Ash.Changeset.for_create(:create, attrs)
          |> Ash.create()
        rescue
          e -> Logger.warning("TokenUsage record failed: #{inspect(e)}")
        end
      end)
    end

    :ok
  end

  def record_usage(_, _), do: :ok

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
            label: map["source_app"] || AgentEntry.short_id(sid),
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

  # Rough cost estimation per 1M tokens (in cents)
  @spec estimate_cost_cents(String.t() | nil, integer(), integer(), integer()) :: integer()
  defp estimate_cost_cents(model, input, output, cache_read) do
    {in_rate, out_rate, cache_rate} =
      cond do
        model && String.contains?(model, "opus") -> {1500, 7500, 150}
        model && String.contains?(model, "sonnet") -> {300, 1500, 30}
        model && String.contains?(model, "haiku") -> {80, 400, 8}
        true -> {300, 1500, 30}
      end

    trunc((input * in_rate + output * out_rate + cache_read * cache_rate) / 1_000_000)
  end

  defp usage_field(raw, key) do
    raw[key] || get_in(raw, ["usage", key]) || 0
  end
end
