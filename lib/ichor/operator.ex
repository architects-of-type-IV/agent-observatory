defmodule Ichor.Operator do
  @moduledoc """
  Unified operator messaging interface.

  Two delivery paths:
    1. BEAM-native: AgentProcess.send_message (GenServer.cast)
    2. Tmux direct: Registry metadata lookup -> Tmux.deliver

  Targets:
    - `"agent:<session_id>"` or `"session:<session_id>"` -- single agent
    - `"team:<name>"` -- all members of a team
    - `"fleet:all"` -- all active agents
    - raw session_id string -- treated as agent target
  """

  alias Ichor.Fleet.{AgentProcess, TeamSupervisor}
  alias Ichor.Gateway.Channels.Tmux

  @from "operator"
  @type_iv_registry Ichor.Registry

  # In-memory message log for comms panel. Capped at 200 entries.
  # TODO: replace with persistent storage when needed.
  @message_log_name :ichor_message_log
  @max_messages 200

  def start_message_log do
    :ets.new(@message_log_name, [:named_table, :public, :ordered_set])
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc "Read recent messages for the comms panel."
  @spec recent_messages(pos_integer()) :: [map()]
  def recent_messages(limit \\ 50) do
    :ets.tab2list(@message_log_name)
    |> Enum.sort_by(fn {ts, _} -> ts end, {:desc, DateTime})
    |> Enum.take(limit)
    |> Enum.map(fn {_ts, msg} -> msg end)
  rescue
    ArgumentError -> []
  end

  @doc """
  Spawn a new agent in a tmux session with instruction overlay.

  Delegates to AgentSpawner. Returns `{:ok, agent_info}` or `{:error, reason}`.
  """
  defdelegate spawn_agent(opts), to: Ichor.AgentSpawner

  @doc """
  Stop a spawned agent by session name.
  """
  defdelegate stop_agent(session_name), to: Ichor.AgentSpawner

  @doc """
  Send a message to any target. Returns `{:ok, delivered_count}` or `{:error, reason}`.

  Uses BEAM-native AgentProcess delivery. Falls back to direct tmux delivery
  via Registry metadata when no BEAM process exists.
  """
  def send(target, content, opts \\ []) when is_binary(target) and is_binary(content) do
    channel = normalize_target(target)

    payload = %{
      content: content,
      from: @from,
      type: Keyword.get(opts, :type, :text),
      metadata: Keyword.get(opts, :metadata, %{})
    }

    case channel do
      "team:" <> name -> deliver_to_team(name, payload)
      "fleet:all" -> deliver_to_fleet(payload)
      _ -> deliver_to_agent(extract_id(channel), payload)
    end
  end

  # ── Delivery ──────────────────────────────────────────────────────────

  defp deliver_to_agent(id, payload) do
    result =
      if AgentProcess.alive?(id) do
        AgentProcess.send_message(id, payload)
        {:ok, 1}
      else
        # Fallback: direct tmux using Registry metadata
        case Registry.lookup(@type_iv_registry, {:agent, id}) do
          [{_pid, %{tmux_target: target}}] when is_binary(target) ->
            Tmux.deliver(target, payload)
            {:ok, 1}

          _ ->
            {:ok, 0}
        end
      end

    case result do
      {:ok, n} when n > 0 -> record_message(@from, id, payload)
      _ -> :ok
    end

    result
  end

  defp deliver_to_team(name, payload) do
    if TeamSupervisor.exists?(name) do
      ids = TeamSupervisor.member_ids(name)

      Enum.each(ids, fn id ->
        AgentProcess.send_message(id, payload)
        record_message(@from, id, payload)
      end)

      {:ok, length(ids)}
    else
      {:ok, 0}
    end
  end

  defp deliver_to_fleet(payload) do
    agents = AgentProcess.list_all()

    Enum.each(agents, fn {id, _meta} ->
      AgentProcess.send_message(id, payload)
      record_message(@from, id, payload)
    end)

    {:ok, length(agents)}
  end

  # ── Message Log ───────────────────────────────────────────────────────

  defp record_message(from, to, payload) do
    now = DateTime.utc_now()

    msg = %{
      id: :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower),
      from: from,
      to: to,
      content: payload[:content] || payload["content"] || "",
      type: payload[:type] || payload["type"] || :text,
      timestamp: now,
      read: false
    }

    try do
      :ets.insert(@message_log_name, {now, msg})

      if :ets.info(@message_log_name, :size) > @max_messages do
        :ets.delete(@message_log_name, :ets.first(@message_log_name))
      end
    rescue
      ArgumentError -> :ok
    end

    Ichor.Signals.emit(:fleet_changed, %{})
  end

  # ── Target Normalization ──────────────────────────────────────────────

  defp extract_id("agent:" <> id), do: id
  defp extract_id("session:" <> id), do: id
  defp extract_id("member:" <> id), do: id
  defp extract_id("role:" <> id), do: id
  defp extract_id(raw), do: raw

  defp normalize_target("agent:" <> _ = channel), do: channel
  defp normalize_target("session:" <> _ = channel), do: channel
  defp normalize_target("team:" <> _ = channel), do: channel
  defp normalize_target("fleet:" <> _ = channel), do: channel
  defp normalize_target("role:" <> _ = channel), do: channel
  defp normalize_target("all"), do: "fleet:all"
  defp normalize_target("all_teams"), do: "fleet:all"
  defp normalize_target("lead:" <> _name), do: "role:lead"
  defp normalize_target("member:" <> sid), do: "session:#{sid}"
  defp normalize_target(id), do: "agent:#{id}"
end
