defmodule ObservatoryWeb.GatewayController do
  use ObservatoryWeb, :controller

  require Logger

  alias Observatory.Gateway.SchemaInterceptor
  alias Observatory.Mesh.DecisionLog
  alias Observatory.Mesh.EntropyTracker

  @doc """
  Accepts a DecisionLog JSON payload from an agent, validates it against the
  DecisionLog schema, and either routes it downstream (HTTP 202) or rejects
  it with a structured error body (HTTP 422).

  This controller MUST NOT be called directly from any LiveView module.
  All LiveView interaction with Gateway data occurs via PubSub subscriptions.
  """
  def create(conn, params) do
    case SchemaInterceptor.validate(params) do
      {:ok, log} ->
        handle_valid(conn, log)

      {:error, changeset} ->
        handle_invalid(conn, changeset, params)
    end
  end

  defp handle_valid(conn, log) do
    updated_log =
      if log.cognition != nil do
        score = EntropyTracker.record_and_score(log.identity.agent_id, log.cognition.entropy_score)

        if is_float(score) do
          DecisionLog.put_gateway_entropy_score(log, score)
        else
          log
        end
      else
        log
      end

    Task.start(fn ->
      case Phoenix.PubSub.broadcast(Observatory.PubSub, "gateway:messages", {:decision_log, updated_log}) do
        :ok -> :ok
        {:error, reason} ->
          Logger.warning("Failed to broadcast decision_log: #{inspect(reason)}")
      end
    end)

    trace_id = if updated_log.meta, do: updated_log.meta.trace_id, else: nil

    conn
    |> put_status(:accepted)
    |> json(%{"status" => "accepted", "trace_id" => trace_id})
  end

  defp handle_invalid(conn, changeset, params) do
    raw_body = conn.assigns[:raw_body]
    event = SchemaInterceptor.build_violation_event(changeset, params, raw_body)

    Task.start(fn ->
      case Phoenix.PubSub.broadcast(Observatory.PubSub, "gateway:violations", {:schema_violation, event}) do
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

      case Phoenix.PubSub.broadcast(Observatory.PubSub, "gateway:topology", {:node_state_update, topology_update}) do
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
