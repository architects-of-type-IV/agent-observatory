defmodule Ichor.Fleet.Comms do
  @moduledoc """
  Unified runtime communications boundary for agents, teams, and fleet targets.
  """

  alias Ichor.Fleet.{AgentProcess, TeamSupervisor}
  alias Ichor.Gateway.Channels.Tmux
  alias Ichor.Gateway.Target

  @from "operator"
  @type_iv_registry Ichor.Registry
  @message_log_name :ichor_message_log
  @max_messages 200

  def start_message_log do
    :ets.new(@message_log_name, [:named_table, :public, :ordered_set])
    :ok
  rescue
    ArgumentError -> :ok
  end

  @spec recent_messages(pos_integer()) :: [map()]
  def recent_messages(limit \\ 50) do
    :ets.tab2list(@message_log_name)
    |> Enum.sort_by(fn {ts, _} -> ts end, {:desc, DateTime})
    |> Enum.take(limit)
    |> Enum.map(fn {_ts, msg} -> msg end)
  rescue
    ArgumentError -> []
  end

  def send(target, content, opts \\ []) when is_binary(target) and is_binary(content) do
    channel = Target.normalize(target)

    payload = %{
      content: content,
      from: Keyword.get(opts, :from, @from),
      type: Keyword.get(opts, :type, :text),
      metadata: Keyword.get(opts, :metadata, %{})
    }

    case channel do
      "team:" <> name -> deliver_to_team(name, payload)
      "fleet:all" -> deliver_to_fleet(payload)
      "role:" <> _ -> gateway_module().broadcast(channel, payload)
      _ -> deliver_to_agent(Target.extract_id(channel), payload)
    end
    |> tap_delivery(target, payload)
  end

  def notify_session(session_id, content, opts \\ []) when is_binary(session_id) do
    send("session:#{session_id}", content, opts)
  end

  defp deliver_to_agent(id, payload) do
    if AgentProcess.alive?(id) do
      AgentProcess.send_message(id, payload)
      {:ok, 1}
    else
      case Registry.lookup(@type_iv_registry, {:agent, id}) do
        [{_pid, %{tmux_target: target}}] when is_binary(target) ->
          Tmux.deliver(target, payload)
          {:ok, 1}

        _ ->
          gateway_module().broadcast(Target.normalize(id), payload)
      end
    end
  end

  defp deliver_to_team(name, payload) do
    if TeamSupervisor.exists?(name) do
      ids = TeamSupervisor.member_ids(name)

      Enum.each(ids, fn id ->
        AgentProcess.send_message(id, payload)
      end)

      {:ok, length(ids)}
    else
      gateway_module().broadcast("team:#{name}", payload)
    end
  end

  defp deliver_to_fleet(payload) do
    agents = AgentProcess.list_all()

    Enum.each(agents, fn {id, _meta} ->
      AgentProcess.send_message(id, payload)
    end)

    {:ok, length(agents)}
  end

  defp tap_delivery({:ok, delivered} = result, original_target, payload) when delivered > 0 do
    record_message(payload.from, original_target, payload)
    result
  end

  defp tap_delivery(result, _original_target, _payload), do: result

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

  defp gateway_module do
    Application.get_env(:ichor, :fleet_comms_gateway_module, Ichor.Gateway.Router)
  end
end
