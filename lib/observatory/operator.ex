defmodule Observatory.Operator do
  @moduledoc """
  Unified operator messaging interface.

  All messages from the dashboard operator go through this module.
  Handles target resolution and routes through Gateway.Router for
  protocol-agnostic, exactly-once delivery.

  Targets:
    - `"agent:<session_id>"` or `"session:<session_id>"` -- single agent
    - `"team:<name>"` -- all members of a team
    - `"fleet:all"` -- all active agents
    - raw session_id string -- treated as agent target
  """

  alias Observatory.Gateway.Router
  alias Observatory.Fleet.{AgentProcess, TeamSupervisor}

  @from "operator"

  @doc """
  Spawn a new agent in a tmux session with instruction overlay.

  Delegates to AgentSpawner. Returns `{:ok, agent_info}` or `{:error, reason}`.
  """
  defdelegate spawn_agent(opts), to: Observatory.AgentSpawner

  @doc """
  Stop a spawned agent by session name.
  """
  defdelegate stop_agent(session_name), to: Observatory.AgentSpawner

  @doc """
  Send a message to any target. Returns `{:ok, delivered_count}` or `{:error, reason}`.

  Tries BEAM-native AgentProcess first (instant GenServer.cast delivery).
  Falls back to Gateway.Router.broadcast for agents not yet migrated to processes.
  """
  def send(target, content, opts \\ []) when is_binary(target) and is_binary(content) do
    channel = normalize_target(target)
    msg_type = Keyword.get(opts, :type, :text)
    metadata = Keyword.get(opts, :metadata, %{})

    payload = %{
      content: content,
      from: @from,
      type: msg_type,
      metadata: metadata
    }

    # Try BEAM-native delivery first for single-agent targets
    case try_native_delivery(channel, payload) do
      {:ok, count} when count > 0 ->
        {:ok, count}

      _ ->
        # Fall back to Gateway.Router for legacy agents or pattern targets
        case Router.broadcast(channel, payload) do
          {:ok, 0} ->
            fallback_deliver(channel, content, msg_type, metadata)

          other ->
            other
        end
    end
  end

  # Deliver via AgentProcess if the target has a living process
  defp try_native_delivery("agent:" <> id, payload) do
    deliver_to_process(id, payload)
  end

  defp try_native_delivery("session:" <> id, payload) do
    deliver_to_process(id, payload)
  end

  defp try_native_delivery("team:" <> name, payload) do
    if TeamSupervisor.exists?(name) do
      ids = TeamSupervisor.member_ids(name)

      Enum.each(ids, fn id ->
        AgentProcess.send_message(id, payload)
      end)

      {:ok, length(ids)}
    else
      {:ok, 0}
    end
  end

  defp try_native_delivery("fleet:all", payload) do
    agents = AgentProcess.list_all()

    if agents != [] do
      Enum.each(agents, fn {id, _meta} ->
        AgentProcess.send_message(id, payload)
      end)

      {:ok, length(agents)}
    else
      {:ok, 0}
    end
  end

  defp try_native_delivery(_channel, _payload), do: {:ok, 0}

  defp deliver_to_process(id, payload) do
    if AgentProcess.alive?(id) do
      AgentProcess.send_message(id, payload)
      {:ok, 1}
    else
      {:ok, 0}
    end
  end

  defp fallback_deliver("team:" <> _name, _content, _type, _metadata), do: {:ok, 0}
  defp fallback_deliver("fleet:" <> _, _content, _type, _metadata), do: {:ok, 0}
  defp fallback_deliver("role:" <> _, _content, _type, _metadata), do: {:ok, 0}

  defp fallback_deliver(target, content, msg_type, metadata) do
    session_id =
      case target do
        "agent:" <> sid -> sid
        "session:" <> sid -> sid
        "member:" <> sid -> sid
        raw -> raw
      end

    case Observatory.Mailbox.send_message(session_id, @from, content,
           type: msg_type,
           metadata: Map.put(metadata, :via_fallback, true)
         ) do
      {:ok, _msg} -> {:ok, 1}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_target("agent:" <> _ = channel), do: channel
  defp normalize_target("session:" <> _ = channel), do: channel
  defp normalize_target("team:" <> _ = channel), do: channel
  defp normalize_target("fleet:" <> _ = channel), do: channel
  defp normalize_target("role:" <> _ = channel), do: channel
  defp normalize_target("all"), do: "fleet:all"
  defp normalize_target("all_teams"), do: "fleet:all"
  defp normalize_target("lead:" <> _name), do: "role:lead"
  defp normalize_target("member:" <> sid), do: "session:#{sid}"
  # Raw session_id or agent name
  defp normalize_target(id), do: "agent:#{id}"
end
