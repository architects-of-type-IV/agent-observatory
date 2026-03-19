defmodule Ichor.Archon.SignalManager.Reactions do
  @moduledoc """
  Pure signal-to-state projection for Archon's managerial view.
  """

  alias Ichor.Signals.Message

  @max_attention 25

  @type attention_item :: %{
          key: String.t(),
          signal: atom(),
          category: atom(),
          severity: :high | :critical,
          summary: String.t(),
          at: integer(),
          data: map()
        }

  @type state :: %{
          signal_count: non_neg_integer(),
          counts_by_category: %{optional(atom()) => non_neg_integer()},
          latest_by_category: %{optional(atom()) => map()},
          attention: [attention_item()]
        }

  @spec new_state() :: state()
  def new_state do
    %{
      signal_count: 0,
      counts_by_category: %{},
      latest_by_category: %{},
      attention: []
    }
  end

  @spec ingest(Message.t(), state()) :: state()
  def ingest(%Message{} = message, state) do
    message
    |> update_counts(state)
    |> update_latest(message)
    |> resolve_attention(message)
    |> add_attention(message)
  end

  defp update_counts(%Message{domain: category}, state) do
    %{
      state
      | signal_count: state.signal_count + 1,
        counts_by_category: Map.update(state.counts_by_category, category, 1, &(&1 + 1))
    }
  end

  defp update_latest(state, %Message{} = message) do
    latest = %{
      name: message.name,
      at: message.timestamp,
      summary: signal_summary(message.name, message.data),
      data: project_data(message.data)
    }

    put_in(state, [:latest_by_category, message.domain], latest)
  end

  defp resolve_attention(state, %Message{name: name, data: data}) do
    keys =
      case {name, data} do
        {:dag_run_completed, %{run_id: run_id}} ->
          ["dag:run:#{run_id}"]

        {:dag_run_archived, %{run_id: run_id}} ->
          ["dag:run:#{run_id}"]

        {:mes_quality_gate_passed, %{run_id: run_id, gate: gate}} ->
          ["mes:gate:#{run_id}:#{gate}"]

        {:gate_passed, %{session_id: session_id, task_id: task_id}} ->
          ["monitoring:gate:#{session_id}:#{inspect(task_id)}"]

        _ ->
          []
      end

    %{state | attention: Enum.reject(state.attention, &(&1.key in keys))}
  end

  defp add_attention(state, %Message{name: name} = message) do
    case attention_item(name, message) do
      nil ->
        state

      item ->
        deduped = [item | Enum.reject(state.attention, &(&1.key == item.key))]
        %{state | attention: Enum.take(deduped, @max_attention)}
    end
  end

  defp attention_item(name, %Message{} = message) do
    case attention_meta(name, message.data) do
      {:ok, severity, key} ->
        %{
          key: key,
          signal: name,
          category: message.domain,
          severity: severity,
          summary: signal_summary(name, message.data),
          at: message.timestamp,
          data: project_data(message.data)
        }

      _ ->
        nil
    end
  end

  defp attention_meta(:dag_tmux_gone, %{run_id: run_id}),
    do: {:ok, :critical, "dag:run:#{run_id}"}

  defp attention_meta(:dag_job_failed, %{run_id: run_id}), do: {:ok, :high, "dag:run:#{run_id}"}

  defp attention_meta(:mes_cycle_failed, %{run_id: run_id}),
    do: {:ok, :critical, "mes:run:#{run_id}"}

  defp attention_meta(:mes_team_spawn_failed, %{session: session}),
    do: {:ok, :critical, "mes:session:#{session}"}

  defp attention_meta(:mes_cycle_timeout, %{run_id: run_id}),
    do: {:ok, :high, "mes:run:#{run_id}"}

  defp attention_meta(:mes_quality_gate_failed, %{run_id: run_id, gate: gate}),
    do: {:ok, :high, "mes:gate:#{run_id}:#{gate}"}

  defp attention_meta(:genesis_team_spawn_failed, %{session: session}),
    do: {:ok, :high, "genesis:session:#{session}"}

  defp attention_meta(:genesis_tmux_gone, %{run_id: run_id}),
    do: {:ok, :critical, "genesis:run:#{run_id}"}

  defp attention_meta(:agent_crashed, %{session_id: session_id}),
    do: {:ok, :critical, "agent:#{session_id}"}

  defp attention_meta(:nudge_zombie, %{session_id: session_id}),
    do: {:ok, :critical, "agent:#{session_id}"}

  defp attention_meta(:nudge_escalated, %{session_id: session_id}),
    do: {:ok, :high, "agent:#{session_id}"}

  defp attention_meta(:gate_failed, %{session_id: session_id, task_id: task_id}),
    do: {:ok, :high, "monitoring:gate:#{session_id}:#{inspect(task_id)}"}

  defp attention_meta(:schema_violation, _data), do: {:ok, :high, "gateway:schema"}
  defp attention_meta(:dead_letter, _data), do: {:ok, :high, "gateway:dead_letter"}
  defp attention_meta(_, _), do: :ignore

  defp signal_summary(:dag_tmux_gone, %{run_id: run_id, session: session}) do
    "DAG run #{run_id} lost tmux session #{session}"
  end

  defp signal_summary(:dag_job_failed, %{external_id: external_id, run_id: run_id}) do
    "DAG job #{external_id} failed in run #{run_id}"
  end

  defp signal_summary(:mes_quality_gate_failed, %{run_id: run_id, gate: gate, reason: reason}) do
    "MES gate #{gate} failed for run #{run_id}: #{reason}"
  end

  defp signal_summary(:mes_team_spawn_failed, %{session: session, reason: reason}) do
    "MES team #{session} failed to spawn: #{reason}"
  end

  defp signal_summary(:agent_crashed, %{session_id: session_id, team_name: team_name}) do
    "Agent #{session_id} crashed#{suffix(" in team #{team_name}")}"
  end

  defp signal_summary(:nudge_zombie, %{agent_name: agent_name, session_id: session_id}) do
    "Agent #{agent_name || session_id} is unresponsive"
  end

  defp signal_summary(name, data) do
    details =
      data
      |> project_data()
      |> Enum.map_join(" ", fn {key, value} -> "#{key}=#{inspect(value)}" end)

    [Atom.to_string(name), details]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  defp project_data(data) do
    data
    |> Enum.reject(fn {key, _value} -> key in [:scope_id, :output, :event_map, :log] end)
    |> Enum.take(6)
    |> Map.new()
  end

  defp suffix(value) when value in [nil, ""], do: ""
  defp suffix(value), do: value
end
