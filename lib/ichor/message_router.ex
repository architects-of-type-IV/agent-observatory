defmodule Ichor.MessageRouter do
  @moduledoc """
  Single delivery authority for all ICHOR messaging.

  Every message in the system flows through `send/1`. One function, one path,
  one place for logging, one place for signal emission. Replaces the former
  Fleet.Comms, Tools.Messaging, and Operator.send delegation chain.
  """

  require Logger

  alias Ichor.Fleet.{AgentProcess, TeamSupervisor}
  alias Ichor.Gateway.Channels.Tmux
  alias Ichor.MessageRouter.Target
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
    target = Target.resolve(to)

    {:ok, delivered} = deliver(target, message)
    log_delivery(from, to, message)
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
    agents = AgentProcess.list_all()
    Enum.each(agents, fn {id, _meta} -> AgentProcess.send_message(id, msg) end)
    {:ok, length(agents)}
  end

  defp deliver_to_role(role, msg) do
    role_atom = String.to_existing_atom(role)

    agents =
      AgentProcess.list_all()
      |> Enum.filter(fn {_id, meta} -> meta[:role] == role_atom end)

    Enum.each(agents, fn {id, _} -> AgentProcess.send_message(id, msg) end)
    {:ok, length(agents)}
  rescue
    ArgumentError -> {:ok, 0}
  end

  defp normalize(from, content, attrs) do
    %{
      content: content,
      from: to_string(from),
      type: Map.get(attrs, :type, :text),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end

  defp log_delivery(from, to, message) do
    now = DateTime.utc_now()

    msg = %{
      id: :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower),
      from: to_string(from),
      to: to,
      content: message.content,
      type: message.type,
      timestamp: now,
      read: false
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
