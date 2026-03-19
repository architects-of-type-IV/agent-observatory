defmodule Ichor.MessageRouter do
  @moduledoc """
  Single delivery authority for all ICHOR messaging.

  Every message in the system flows through `send/1`. One function, one path,
  one place for logging, one place for signal emission. Replaces the former
  Fleet.Comms, Tools.Messaging, and Operator.send delegation chain.
  """

  require Logger

  alias Ichor.Control.{AgentProcess, TeamSupervisor}
  alias Ichor.Gateway.Channels.Tmux
  alias Ichor.Signals

  @message_log :ichor_message_log
  @max_messages 200

  @doc """
  Send a message to any target. Returns `{:ok, %{status, to, delivered}}`.

  Required keys: `:from`, `:to`, `:content` (all binaries).
  Optional keys: `:type` (default `:text`), `:metadata` (default `%{}`).
  """
  @spec send(map()) :: {:ok, map()} | {:error, String.t()}
  def send(%{from: from, to: to, content: content} = attrs)
      when is_binary(to) and is_binary(content) do
    message = normalize(from, content, attrs)
    target = resolve_target(to)

    {:ok, delivered} = deliver(target, message)
    log_delivery(from, to, message, attrs)
    {:ok, %{status: "sent", to: to, delivered: delivered}}
  end

  def send(%{to: _to, content: _content} = attrs) do
    send(Map.put_new(attrs, :from, "system"))
  end

  def send(_), do: {:error, "missing required keys: :from, :to, :content"}

  @doc "Initialize the ETS message log. Called at application start."
  @spec start_message_log() :: :ok
  def start_message_log do
    :ets.new(@message_log, [:named_table, :public, :ordered_set])
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc "Read recent messages from the ETS log, newest first."
  @spec recent_messages(pos_integer()) :: [map()]
  def recent_messages(limit \\ 50) do
    @message_log
    |> :ets.tab2list()
    |> Enum.sort_by(fn {ts, _} -> ts end, {:desc, DateTime})
    |> Enum.take(limit)
    |> Enum.map(fn {_ts, msg} -> msg end)
  rescue
    ArgumentError -> []
  end

  defp resolve_target("team:" <> name), do: {:team, name}
  defp resolve_target("fleet:all"), do: {:fleet, :all}
  defp resolve_target("role:" <> role), do: {:role, role}
  defp resolve_target("session:" <> sid), do: {:session, sid}
  defp resolve_target("agent:" <> id), do: {:agent, id}
  defp resolve_target(id) when is_binary(id), do: {:agent, id}

  defp deliver({:agent, id}, msg), do: deliver_to_agent(id, msg)
  defp deliver({:session, sid}, msg), do: deliver_to_agent(sid, msg)
  defp deliver({:team, name}, msg), do: deliver_to_team(name, msg)
  defp deliver({:fleet, :all}, msg), do: deliver_to_fleet(msg)
  defp deliver({:role, role}, msg), do: deliver_to_role(role, msg)

  defp deliver_to_agent(id, msg) do
    case AgentProcess.alive?(id) do
      true ->
        AgentProcess.send_message(id, msg)
        {:ok, 1}

      false ->
        case Registry.lookup(Ichor.Registry, {:agent, id}) do
          [{_pid, %{tmux_target: target}}] when is_binary(target) ->
            Tmux.deliver(target, msg)
            {:ok, 1}

          _ ->
            {:ok, 0}
        end
    end
  end

  defp deliver_to_team(name, msg) do
    case TeamSupervisor.exists?(name) do
      true ->
        ids = TeamSupervisor.member_ids(name)
        Enum.each(ids, &AgentProcess.send_message(&1, msg))
        {:ok, length(ids)}

      false ->
        {:ok, 0}
    end
  end

  defp deliver_to_fleet(msg) do
    count =
      AgentProcess.list_all()
      |> Enum.reduce(0, fn {id, _}, acc ->
        AgentProcess.send_message(id, msg)
        acc + 1
      end)

    {:ok, count}
  end

  @role_map %{"coordinator" => :coordinator, "lead" => :lead, "worker" => :worker}

  defp deliver_to_role(role, msg) do
    case Map.fetch(@role_map, role) do
      {:ok, role_atom} ->
        count =
          AgentProcess.list_all()
          |> Enum.reduce(0, fn
            {id, %{role: ^role_atom}}, acc ->
              AgentProcess.send_message(id, msg)
              acc + 1

            _, acc ->
              acc
          end)

        {:ok, count}

      :error ->
        {:ok, 0}
    end
  end

  defp normalize(from, content, attrs) do
    %{
      content: content,
      from: to_string(from),
      type: Map.get(attrs, :type, :text),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end

  defp log_delivery(from, to, message, attrs) do
    now = DateTime.utc_now()

    msg = %{
      id: :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower),
      from: to_string(from),
      to: to,
      content: message.content,
      type: message.type,
      timestamp: now,
      read: false,
      sender_app: Map.get(attrs, :sender_app),
      summary: nil,
      transport: Map.get(attrs, :transport, :http)
    }

    try do
      :ets.insert(@message_log, {now, msg})

      if :ets.info(@message_log, :size) > @max_messages do
        :ets.delete(@message_log, :ets.first(@message_log))
      end
    rescue
      ArgumentError -> :ok
    end

    Signals.emit(:fleet_changed, %{})
  end
end
