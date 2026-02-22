defmodule ObservatoryWeb.HITLController do
  @moduledoc """
  HTTP endpoints for HITL (Human-In-The-Loop) operator commands.

  All actions require the `x-observatory-operator-id` header (enforced by
  the `:hitl_auth` pipeline). Each successful command creates an audit trail
  entry in `hitl_intervention_events`.
  """

  use ObservatoryWeb, :controller

  alias Observatory.Gateway.HITLRelay
  alias Observatory.Gateway.HITLInterventionEvent
  alias Observatory.Repo

  def pause(conn, %{"agent_id" => agent_id, "reason" => reason} = _params)
      when is_binary(agent_id) and agent_id != "" and is_binary(reason) and reason != "" do
    session_id = conn.params["session_id"]
    operator_id = conn.assigns.operator_id

    case HITLRelay.pause(session_id, agent_id, operator_id, reason) do
      :ok ->
        audit!(session_id, agent_id, operator_id, "pause", %{reason: reason})
        json(conn, %{status: "ok"})

      {:ok, :already_paused} ->
        audit!(session_id, agent_id, operator_id, "pause", %{reason: reason, note: "already_paused"})
        json(conn, %{status: "ok", note: "already_paused"})
    end
  end

  def pause(conn, _params) do
    conn |> put_status(422) |> json(%{status: "error", reason: "missing_required_fields", fields: ["agent_id", "reason"]})
  end

  def unpause(conn, %{"agent_id" => agent_id} = _params)
      when is_binary(agent_id) and agent_id != "" do
    session_id = conn.params["session_id"]
    operator_id = conn.assigns.operator_id

    case HITLRelay.unpause(session_id, agent_id, operator_id) do
      {:ok, flushed_count} when is_integer(flushed_count) ->
        audit!(session_id, agent_id, operator_id, "unpause", %{flushed_count: flushed_count})
        json(conn, %{status: "ok", flushed_count: flushed_count})

      {:ok, :not_paused} ->
        json(conn, %{status: "ok", note: "not_paused"})
    end
  end

  def unpause(conn, _params) do
    conn |> put_status(422) |> json(%{status: "error", reason: "missing_required_fields", fields: ["agent_id"]})
  end

  def rewrite(conn, %{"trace_id" => trace_id, "new_payload" => new_payload} = _params)
      when is_binary(trace_id) and trace_id != "" do
    session_id = conn.params["session_id"]
    operator_id = conn.assigns.operator_id

    case HITLRelay.rewrite(session_id, trace_id, new_payload) do
      :ok ->
        audit!(session_id, nil, operator_id, "rewrite", %{trace_id: trace_id})
        json(conn, %{status: "ok"})

      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{status: "error", reason: "not_found"})
    end
  end

  def rewrite(conn, _params) do
    conn |> put_status(422) |> json(%{status: "error", reason: "missing_required_fields", fields: ["trace_id", "new_payload"]})
  end

  def inject(conn, %{"agent_id" => agent_id, "payload" => payload} = _params)
      when is_binary(agent_id) and agent_id != "" do
    session_id = conn.params["session_id"]
    operator_id = conn.assigns.operator_id

    :ok = HITLRelay.inject(session_id, agent_id, payload)
    audit!(session_id, agent_id, operator_id, "inject", %{})
    json(conn, %{status: "ok"})
  end

  def inject(conn, _params) do
    conn |> put_status(422) |> json(%{status: "error", reason: "missing_required_fields", fields: ["agent_id", "payload"]})
  end

  defp audit!(session_id, agent_id, operator_id, action, details) do
    %HITLInterventionEvent{}
    |> HITLInterventionEvent.changeset(%{
      session_id: session_id,
      agent_id: agent_id,
      operator_id: operator_id,
      action: action,
      details: Jason.encode!(details)
    })
    |> Repo.insert!()
  end
end
