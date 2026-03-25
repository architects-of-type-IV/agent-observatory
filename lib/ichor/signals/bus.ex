defmodule Ichor.Signals.Bus do
  @moduledoc """
  Single delivery authority for all ICHOR messaging.

  Every message in the system flows through `send/1`. One function, one path,
  one place for logging, one place for signal emission. Replaces MessageRouter
  as the canonical message bus.
  """

  require Logger

  alias Ichor.Events
  alias Ichor.Events.Event
  alias Ichor.Fleet.AgentProcess
  alias Ichor.Fleet.TeamSupervisor
  alias Ichor.Infrastructure.Tmux

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
    target = resolve(to)

    case deliver(target, message) do
      {:ok, delivered} ->
        log_delivery(from, to, message, attrs)
        broadcast_delivery(to, from, message, delivered)
        {:ok, %{status: "sent", to: to, delivered: delivered}}
    end
  end

  def send(%{to: to, content: _content} = attrs) do
    Logger.warning("[Bus] Message sent without :from, defaulting to system: #{inspect(to)}")
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
    |> Enum.sort_by(fn {seq, _} -> seq end, :desc)
    |> Enum.take(limit)
    |> Enum.map(fn {_ts, msg} -> msg end)
  rescue
    ArgumentError -> []
  end

  @doc """
  Resolve a target string to a tagged tuple.

  Returns one of:
  - `{:agent, id}`
  - `{:team, name}`
  - `{:fleet, :all}`
  - `{:role, role}`
  - `{:session, sid}`
  """
  @spec resolve(String.t()) ::
          {:agent, String.t()}
          | {:team, String.t()}
          | {:fleet, :all}
          | {:role, String.t()}
          | {:session, String.t()}
  def resolve("team:" <> name), do: {:team, name}
  def resolve("fleet:all"), do: {:fleet, :all}
  def resolve("role:" <> role), do: {:role, role}
  def resolve("session:" <> sid), do: {:session, sid}
  def resolve("agent:" <> id), do: {:agent, id}
  def resolve(id) when is_binary(id), do: {:agent, id}

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
    Enum.each(agents, fn {id, _} -> AgentProcess.send_message(id, msg) end)
    {:ok, length(agents)}
  end

  @role_map %{"coordinator" => :coordinator, "lead" => :lead, "worker" => :worker}

  defp deliver_to_role(role, msg) do
    case Map.fetch(@role_map, role) do
      {:ok, role_atom} ->
        matching = Enum.filter(AgentProcess.list_all(), fn {_, %{role: r}} -> r == role_atom end)
        Enum.each(matching, fn {id, _} -> AgentProcess.send_message(id, msg) end)
        {:ok, length(matching)}

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
    seq = System.monotonic_time(:microsecond)

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
      :ets.insert(@message_log, {seq, msg})

      if :ets.info(@message_log, :size) > @max_messages do
        :ets.delete(@message_log, :ets.first(@message_log))
      end
    rescue
      ArgumentError -> :ok
    end

    Events.emit(Event.new("fleet.registry.changed", nil, %{}))
  end

  defp broadcast_delivery(to, from, message, delivered) do
    msg_map = Map.merge(message, %{to: to, from: to_string(from)})

    Events.emit(Event.new("messages.delivered", to, %{agent_id: to, msg_map: msg_map}))

    if delivered == 0 do
      Logger.warning(
        "[Bus] Message to #{inspect(to)} from #{inspect(from)} dropped: no agent or tmux target found"
      )
    end
  end
end
