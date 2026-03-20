defmodule IchorWeb.GatewayController do
  @moduledoc "Receives DecisionLog payloads from agents, validates schema, and routes downstream."

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
    end
  end

  defp handle_valid(conn, log) do
    Ichor.Signals.emit(:decision_log, %{log: log})

    trace_id = if log.meta, do: log.meta["trace_id"] || log.meta[:trace_id], else: nil

    conn
    |> put_status(:accepted)
    |> json(%{"status" => "accepted", "trace_id" => trace_id})
  end
end
