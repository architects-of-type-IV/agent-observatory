defmodule IchorWeb.GatewayController do
  use IchorWeb, :controller

  require Logger

  alias Ichor.Gateway.SchemaInterceptor

  @doc """
  Accepts a DecisionLog JSON payload from an agent, validates it against the
  DecisionLog schema, and either routes it downstream (HTTP 202) or rejects
  it with a structured error body (HTTP 422).

  This controller MUST NOT be called directly from any LiveView module.
  All LiveView interaction with Gateway data occurs via PubSub subscriptions.
  """
  def create(conn, params) do
    case SchemaInterceptor.validate_and_enrich(params) do
      {:ok, log} ->
        handle_valid(conn, log)

      {:error, changeset} ->
        handle_invalid(conn, changeset, params)
    end
  end

  defp handle_valid(conn, log) do
    Task.start(fn ->
      case Phoenix.PubSub.broadcast(Ichor.PubSub, "gateway:messages", {:decision_log, log}) do
        :ok -> :ok
        {:error, reason} ->
          Logger.warning("Failed to broadcast decision_log: #{inspect(reason)}")
      end
    end)

    trace_id = if log.meta, do: log.meta.trace_id, else: nil

    conn
    |> put_status(:accepted)
    |> json(%{"status" => "accepted", "trace_id" => trace_id})
  end

  defp handle_invalid(conn, changeset, params) do
    raw_body = conn.assigns[:raw_body]
    event = SchemaInterceptor.build_violation_event(changeset, params, raw_body)

    Task.start(fn ->
      case Phoenix.PubSub.broadcast(Ichor.PubSub, "gateway:violations", {:schema_violation, event}) do
        :ok -> :ok
        {:error, reason} ->
          Logger.warning("Failed to broadcast schema_violation event: #{inspect(reason)}")
      end
    end)

    Task.start(fn ->
      topology_update = %{
        agent_id: event["agent_id"],
        state: :schema_violation,
        clear_after_ms: 30_000,
        timestamp: event["timestamp"]
      }

      case Phoenix.PubSub.broadcast(Ichor.PubSub, "gateway:topology", {:node_state_update, topology_update}) do
        :ok -> :ok
        {:error, reason} ->
          Logger.warning("Failed to broadcast topology node_state_update: #{inspect(reason)}")
      end
    end)

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      "status" => "rejected",
      "reason" => "schema_violation",
      "detail" => event["violation_reason"],
      "trace_id" => nil
    })
  end
end
