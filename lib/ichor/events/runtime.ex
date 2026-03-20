defmodule Ichor.Events.Runtime do
  @moduledoc """
  Unified event runtime. Canonical entry point for all inbound events.

  Wraps EventBuffer and HeartbeatManager during the migration period.
  Future steps will internalize those subsystems here.

  Public API:
  - `ingest_raw/1`        -- normalize a raw hook map, store, and emit signals
  - `record_heartbeat/2`  -- normalize a heartbeat into an Event, update liveness
  - `publish_fact/2`      -- publish an internal fact (watchdog probes, etc.)
  - `subscribe/2`         -- subscribe to the normalized event stream
  - `latest_session_state/1` -- liveness/alias/last-seen for a session
  """

  alias Ichor.EventBuffer
  alias Ichor.Events.Event
  alias Ichor.Gateway.{HeartbeatManager, Router}
  alias Ichor.Signals

  @doc "Ingest a raw hook event map. Normalizes, stores, emits signals, and runs side effects."
  @spec ingest_raw(map()) :: {:ok, map()}
  def ingest_raw(raw_map) when is_map(raw_map) do
    {:ok, event} = EventBuffer.ingest(raw_map)
    Signals.emit(:new_event, %{event: event})
    Router.ingest(event)
    {:ok, event}
  end

  @doc "Record a heartbeat for an agent session. Delegates to HeartbeatManager."
  @spec record_heartbeat(String.t(), String.t()) :: :ok
  def record_heartbeat(agent_id, cluster_id)
      when is_binary(agent_id) and is_binary(cluster_id) do
    HeartbeatManager.record_heartbeat(agent_id, cluster_id)
  end

  @doc "Publish an internal fact (watchdog probes, system events, etc.)."
  @spec publish_fact(atom(), map()) :: :ok
  def publish_fact(name, attrs \\ %{}) when is_atom(name) and is_map(attrs) do
    _event = build_fact_event(name, attrs)
    Signals.emit(:new_event, %{name: name, attrs: attrs})
    :ok
  end

  @doc "Subscribe to the normalized event stream. Delegates to Signals."
  @spec subscribe(atom(), keyword()) :: :ok | {:error, term()}
  def subscribe(topic, opts \\ []) when is_atom(topic) do
    case Keyword.get(opts, :scope_id) do
      nil -> Signals.subscribe(topic)
      scope_id -> Signals.subscribe(topic, scope_id)
    end
  end

  @doc "Returns liveness metadata for a session from the heartbeat store."
  @spec latest_session_state(String.t()) :: map() | nil
  def latest_session_state(session_id) when is_binary(session_id) do
    HeartbeatManager.get_session_state(session_id)
  end

  # Private helpers

  defp build_fact_event(name, attrs) do
    %Event{
      id: Ash.UUID.generate(),
      kind: :fact,
      name: name,
      session_id: attrs[:session_id],
      payload: attrs,
      timestamp: DateTime.utc_now()
    }
  end
end
