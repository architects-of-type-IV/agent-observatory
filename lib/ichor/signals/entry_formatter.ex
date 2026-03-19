defmodule Ichor.Signals.EntryFormatter do
  @moduledoc "Transforms signal messages into structured stream entries."

  alias Ichor.Signals.{Catalog, Message, StreamEntry}

  @spec format(Message.t(), non_neg_integer()) :: StreamEntry.t()
  def format(%Message{} = sig, seq) do
    info = Catalog.lookup(sig.name)

    %StreamEntry{
      seq: seq,
      captured_at: DateTime.utc_now(),
      name: sig.name,
      category: sig.domain,
      topic: "#{sig.domain}:#{sig.name}",
      kind: sig.kind,
      payload: truncate_payload(sig.data),
      summary: summarize(sig.name, sig.domain, sig.data, info)
    }
  end

  # Per-signal summary formatters. Pattern match on signal name.
  # Return %{text: String.t(), fields: [%{key: atom, value: term, display: String.t()}]}

  defp summarize(:heartbeat, _cat, %{count: count}, _info) do
    %{text: "beat ##{count}", fields: [%{key: :count, value: count, display: "#{count}"}]}
  end

  defp summarize(:agent_started, _cat, data, _info) do
    sid = short_id(data[:session_id])

    %{
      text: "#{data[:role]} #{sid} joined#{team_suffix(data[:team])}",
      fields: primary_fields(data, [:session_id, :role, :team])
    }
  end

  defp summarize(:agent_stopped, _cat, data, _info) do
    sid = short_id(data[:session_id])

    %{
      text: "#{sid} stopped (#{data[:reason] || "normal"})",
      fields: primary_fields(data, [:session_id, :reason])
    }
  end

  defp summarize(:agent_paused, _cat, data, _info),
    do: simple("#{short_id(data[:session_id])} paused", data, [:session_id])

  defp summarize(:agent_resumed, _cat, data, _info),
    do: simple("#{short_id(data[:session_id])} resumed", data, [:session_id])

  defp summarize(:agent_evicted, _cat, data, _info),
    do: simple("#{short_id(data[:session_id])} evicted (heartbeat timeout)", data, [:session_id])

  defp summarize(:agent_reaped, _cat, data, _info),
    do: simple("#{short_id(data[:session_id])} reaped (tmux dead)", data, [:session_id])

  defp summarize(:agent_discovered, _cat, data, _info),
    do: simple("discovered #{short_id(data[:session_id])}", data, [:session_id])

  defp summarize(:agent_crashed, _cat, data, _info),
    do: simple("#{short_id(data[:session_id])} crashed", data, [:session_id, :team_name])

  defp summarize(:fleet_changed, _cat, _data, _info),
    do: %{text: "fleet state changed", fields: []}

  defp summarize(:registry_changed, _cat, _data, _info),
    do: %{text: "registry changed", fields: []}

  defp summarize(:team_created, _cat, data, _info),
    do: simple("team #{data[:name]} created", data, [:name, :project])

  defp summarize(:team_disbanded, _cat, data, _info),
    do: simple("team #{data[:team_name]} disbanded", data, [:team_name])

  defp summarize(:message_delivered, _cat, data, _info) do
    msg = data[:msg_map] || %{}
    from = short_id(msg[:from] || msg["from"])
    to = short_id(msg[:to] || msg["to"])
    content = truncate_string(msg[:content] || msg["content"] || "", 60)
    %{text: "#{from} -> #{to}: #{content}", fields: primary_fields(data, [:agent_id])}
  end

  defp summarize(:new_event, _cat, _data, _info), do: %{text: "hook event ingested", fields: []}

  defp summarize(:genesis_artifact_created, _cat, data, _info) do
    %{
      text: "#{data[:type]} created for node #{short_id(data[:node_id])}",
      fields: primary_fields(data, [:id, :node_id, :type])
    }
  end

  defp summarize(:genesis_node_created, _cat, data, _info),
    do: simple("node #{data[:title]} created", data, [:id, :title])

  defp summarize(:genesis_node_advanced, _cat, data, _info),
    do: simple("node #{data[:title]} advanced", data, [:id, :title, :type])

  defp summarize(:genesis_run_complete, _cat, data, _info),
    do: simple("mode #{data[:mode]} completed", data, [:run_id, :mode, :session])

  defp summarize(:genesis_team_ready, _cat, data, _info),
    do:
      simple("#{data[:mode]} team ready (#{data[:agent_count]} agents)", data, [:session, :mode])

  defp summarize(:dag_run_created, _cat, data, _info),
    do: simple("run #{data[:label]} created (#{data[:job_count]} jobs)", data, [:run_id, :label])

  defp summarize(:dag_run_completed, _cat, data, _info),
    do: simple("run #{data[:label]} completed", data, [:run_id, :label])

  defp summarize(:dag_run_ready, _cat, data, _info),
    do: simple("run ready in #{data[:session]}", data, [:run_id, :session])

  defp summarize(:dag_run_archived, _cat, data, _info),
    do: simple("run #{data[:label]} archived", data, [:run_id, :label])

  defp summarize(:dag_job_claimed, _cat, data, _info),
    do:
      simple("job #{data[:external_id]} claimed by #{short_id(data[:owner])}", data, [
        :external_id,
        :owner
      ])

  defp summarize(:dag_job_completed, _cat, data, _info),
    do: simple("job #{data[:external_id]} completed", data, [:external_id, :owner])

  defp summarize(:dag_job_failed, _cat, data, _info),
    do: simple("job #{data[:external_id]} failed", data, [:external_id, :notes])

  defp summarize(:dag_job_reset, _cat, data, _info),
    do: simple("job #{data[:external_id]} reset", data, [:external_id])

  defp summarize(:dag_status, _cat, _data, _info),
    do: %{text: "pipeline status update", fields: []}

  defp summarize(:mes_project_created, _cat, data, _info),
    do: simple("project #{data[:title]} created", data, [:project_id, :title])

  defp summarize(:mes_project_picked_up, _cat, data, _info),
    do: simple("project picked up by #{short_id(data[:session_id])}", data, [:project_id])

  defp summarize(:mes_subsystem_loaded, _cat, data, _info),
    do: simple("subsystem #{data[:subsystem]} loaded", data, [:project_id, :subsystem])

  defp summarize(:mes_team_ready, _cat, data, _info),
    do: simple("team ready (#{data[:agent_count]} agents)", data, [:session])

  defp summarize(:mes_dag_generated, _cat, data, _info),
    do: simple("DAG generated for node #{short_id(data[:node_id])}", data, [:node_id])

  defp summarize(:mes_dag_launched, _cat, data, _info),
    do: simple("DAG launched in #{data[:session]}", data, [:node_id, :session])

  defp summarize(:hitl_auto_released, _cat, data, _info),
    do: simple("auto-released #{short_id(data[:session_id])}", data, [:session_id])

  defp summarize(:hitl_operator_approved, _cat, data, _info),
    do: simple("approved #{short_id(data[:session_id])}", data, [:session_id])

  defp summarize(:hitl_operator_rejected, _cat, data, _info),
    do: simple("rejected #{short_id(data[:session_id])}", data, [:session_id])

  # Catch-all: use catalog keys to build a generic summary
  defp summarize(name, _cat, data, info) do
    keys = (info && info.keys) || Map.keys(data) |> Enum.take(4)
    text = Enum.map_join(keys, " ", fn k -> "#{k}=#{short_val(data[k])}" end)
    %{text: "#{name} #{text}", fields: primary_fields(data, keys)}
  end

  # Helpers

  defp simple(text, data, keys), do: %{text: text, fields: primary_fields(data, keys)}

  defp primary_fields(data, keys) do
    Enum.map(keys, fn k ->
      v = data[k]
      %{key: k, value: v, display: short_val(v)}
    end)
  end

  defp short_id(nil), do: "?"
  defp short_id(id) when is_binary(id) and byte_size(id) > 12, do: String.slice(id, 0, 8)
  defp short_id(id) when is_binary(id), do: id
  defp short_id(id), do: inspect(id)

  defp short_val(nil), do: "nil"
  defp short_val(v) when is_binary(v) and byte_size(v) > 30, do: String.slice(v, 0, 26) <> ".."
  defp short_val(v) when is_binary(v), do: v
  defp short_val(v) when is_atom(v), do: Atom.to_string(v)
  defp short_val(v) when is_number(v), do: to_string(v)
  defp short_val(v), do: inspect(v, limit: 5, printable_limit: 30)

  defp truncate_string(s, max) when byte_size(s) > max, do: String.slice(s, 0, max - 2) <> ".."
  defp truncate_string(s, _max), do: s

  defp truncate_payload(data) when is_map(data) do
    Map.new(data, fn
      {k, v} when is_binary(v) and byte_size(v) > 200 -> {k, String.slice(v, 0, 197) <> "..."}
      {k, v} when is_map(v) -> {k, truncate_payload(v)}
      {k, v} -> {k, v}
    end)
  end

  defp truncate_payload(data), do: data

  defp team_suffix(nil), do: ""
  defp team_suffix(team), do: " in #{team}"
end
